# frozen_string_literal: true

require "rails_helper"

RSpec.describe CognitoTokenVerifier do
  let(:verifier) do
    described_class.new(user_pool_id: CognitoTokenHelper::TEST_USER_POOL_ID, region: CognitoTokenHelper::TEST_REGION)
  end

  before { stub_cognito_jwks }

  describe "#verify" do
    it "accepts a token signed by the pool with the tariff/read scope" do
      result = verifier.verify(signed_cognito_token)

      expect(result.status).to eq(:valid)
      expect(result.client_id).to eq("test-client")
    end

    it "accepts a token that carries tariff/read among other scopes" do
      result = verifier.verify(signed_cognito_token(scope: "tariff/write tariff/read"))

      expect(result.status).to eq(:valid)
    end

    it "falls back to sub for the client_id when the client_id claim is absent" do
      result = verifier.verify(signed_cognito_token(client_id: nil, sub: "subject-client"))

      expect(result.client_id).to eq("subject-client")
    end

    it "rejects a token that is not a JWT" do
      expect(verifier.verify("not-a-jwt").status).to eq(:invalid)
    end

    it "rejects a token with a forged, unsigned payload" do
      payload = Base64.urlsafe_encode64({ client_id: "forged" }.to_json, padding: false)

      expect(verifier.verify("header.#{payload}.signature").status).to eq(:invalid)
    end

    it "rejects a token signed by a key that is not in the pool JWKS" do
      stranger_key = JWT::JWK.new(OpenSSL::PKey::RSA.new(2048), kid: "test-key-1")

      expect(verifier.verify(signed_cognito_token(signing_key: stranger_key)).status).to eq(:invalid)
    end

    it "rejects a token signed with HS256 using the public key as the secret" do
      public_pem = CognitoTokenHelper::TEST_SIGNING_KEY.public_key.to_pem
      token = JWT.encode({ "iss" => CognitoTokenHelper::TEST_ISSUER, "token_use" => "access", "scope" => "tariff/read",
                           "exp" => 1.hour.from_now.to_i }, public_pem, "HS256", kid: "test-key-1")

      expect(verifier.verify(token).status).to eq(:invalid)
    end

    it "rejects an expired token" do
      expect(verifier.verify(signed_cognito_token(exp: 1.minute.ago.to_i)).status).to eq(:invalid)
    end

    it "rejects a token issued by a different user pool" do
      other_issuer = "https://cognito-idp.eu-west-2.amazonaws.com/eu-west-2_OtherPool"

      expect(verifier.verify(signed_cognito_token(iss: other_issuer)).status).to eq(:invalid)
    end

    it "rejects an ID token" do
      expect(verifier.verify(signed_cognito_token(token_use: "id")).status).to eq(:invalid)
    end

    it "rejects a token without the tariff/read scope" do
      expect(verifier.verify(signed_cognito_token(scope: "tariff/categorisation")).status).to eq(:invalid)
    end

    it "rejects a token whose scope only contains tariff/read as a substring" do
      expect(verifier.verify(signed_cognito_token(scope: "tariff/read-extra")).status).to eq(:invalid)
    end

    it "reports unavailable when the JWKS cannot be fetched and none is cached" do
      stub_request(:get, CognitoTokenHelper::TEST_JWKS_URL).to_return(status: 500)

      expect(verifier.verify(signed_cognito_token).status).to eq(:unavailable)
    end

    it "reports unavailable when the JWKS request times out" do
      stub_request(:get, CognitoTokenHelper::TEST_JWKS_URL).to_timeout

      expect(verifier.verify(signed_cognito_token).status).to eq(:unavailable)
    end

    it "fetches the JWKS once and reuses it for later tokens" do
      verifier.verify(signed_cognito_token)
      verifier.verify(signed_cognito_token)

      expect(a_request(:get, CognitoTokenHelper::TEST_JWKS_URL)).to have_been_made.once
    end

    it "refetches the JWKS for an unknown kid once the cached copy is old enough, to follow key rotation" do
      verifier.verify(signed_cognito_token)
      rotated_key = JWT::JWK.new(OpenSSL::PKey::RSA.new(2048), kid: "test-key-2")
      stub_cognito_jwks(signing_key: rotated_key)

      travel_to(10.minutes.from_now) do
        result = verifier.verify(signed_cognito_token(signing_key: rotated_key, exp: 1.hour.from_now.to_i))

        expect(result.status).to eq(:valid)
      end
    end

    it "does not refetch the JWKS for an unknown kid when the cached copy is fresh" do
      verifier.verify(signed_cognito_token)
      unknown_key = JWT::JWK.new(OpenSSL::PKey::RSA.new(2048), kid: "attacker-kid")

      result = verifier.verify(signed_cognito_token(signing_key: unknown_key))

      expect(result.status).to eq(:invalid)
      expect(a_request(:get, CognitoTokenHelper::TEST_JWKS_URL)).to have_been_made.once
    end
  end
end
