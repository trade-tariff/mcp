# frozen_string_literal: true

# Signs real RS256 tokens with a test key and serves the matching public key
# as a Cognito JWKS, so specs exercise the same verification path as
# production instead of stubbing the verifier.
module CognitoTokenHelper
  TEST_USER_POOL_ID = "eu-west-2_TestPool"
  TEST_REGION = "eu-west-2"
  TEST_ISSUER = "https://cognito-idp.#{TEST_REGION}.amazonaws.com/#{TEST_USER_POOL_ID}"
  TEST_JWKS_URL = "#{TEST_ISSUER}/.well-known/jwks.json"
  TEST_SIGNING_KEY = JWT::JWK.new(OpenSSL::PKey::RSA.new(2048), kid: "test-key-1")

  def stub_cognito_jwks(signing_key: TEST_SIGNING_KEY)
    jwks = { keys: [ signing_key.export ] }
    stub_request(:get, TEST_JWKS_URL)
      .to_return(status: 200, body: jwks.to_json, headers: { "Content-Type" => "application/json" })
  end

  def signed_cognito_token(signing_key: TEST_SIGNING_KEY, **claim_overrides)
    claims = {
      "iss" => TEST_ISSUER,
      "sub" => "test-client",
      "client_id" => "test-client",
      "token_use" => "access",
      "scope" => "tariff/read",
      "exp" => 1.hour.from_now.to_i,
      "iat" => Time.current.to_i
    }.merge(claim_overrides.transform_keys(&:to_s)).compact

    JWT.encode(claims, signing_key.signing_key, "RS256", kid: signing_key[:kid])
  end
end
