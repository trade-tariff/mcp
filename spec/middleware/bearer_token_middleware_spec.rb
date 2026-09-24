# frozen_string_literal: true

require "rails_helper"

RSpec.describe BearerTokenMiddleware do
  let(:inner_app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }
  let(:middleware) { described_class.new(inner_app) }

  before do
    CurrentRequest.reset
    stub_cognito_jwks
  end

  def env_for(path: "/", authorization: nil)
    env = Rack::MockRequest.env_for(path)
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    env
  end

  def unsigned_jwt_with_claims(claims)
    payload = Base64.urlsafe_encode64(claims.to_json, padding: false)
    "header.#{payload}.signature"
  end

  context "with a valid Cognito access token" do
    it "passes the request through" do
      status, = middleware.call(env_for(authorization: "Bearer #{signed_cognito_token}"))

      expect(status).to eq(200)
    end

    it "stores the token so it is forwarded to the tariff API" do
      token = signed_cognito_token
      middleware.call(env_for(authorization: "Bearer #{token}"))

      expect(CurrentRequest.bearer_token).to eq(token)
    end

    it "takes the client_id from the verified claims" do
      middleware.call(env_for(authorization: "Bearer #{signed_cognito_token(client_id: "my-client")}"))

      expect(CurrentRequest.client_id).to eq("my-client")
    end

    it "accepts a raw token without the Bearer prefix" do
      status, = middleware.call(env_for(authorization: signed_cognito_token))

      expect(status).to eq(200)
    end

    it "tags log output with the client_id" do
      tagged_messages = []
      allow(Rails.logger).to receive(:tagged) { |tag, &block|
        tagged_messages << tag
        block.call
      }
      middleware.call(env_for(authorization: "Bearer #{signed_cognito_token(client_id: "tagged-client")}"))

      expect(tagged_messages).to include("client_id=tagged-client")
    end
  end

  context "with a token that does not verify" do
    it "returns 401 for an arbitrary string" do
      status, = middleware.call(env_for(authorization: "Bearer my-token"))

      expect(status).to eq(401)
    end

    it "returns 401 for a forged JWT and does not trust its client_id" do
      token = unsigned_jwt_with_claims("client_id" => "forged-client")
      status, = middleware.call(env_for(authorization: "Bearer #{token}"))

      expect(status).to eq(401)
      expect(CurrentRequest.client_id).to be_nil
    end

    it "does not call the inner app" do
      inner_app = ->(_env) { raise "inner app must not be called" }
      status, = described_class.new(inner_app).call(env_for(authorization: "Bearer my-token"))

      expect(status).to eq(401)
    end

    it "marks the WWW-Authenticate challenge as invalid_token" do
      _, headers, = middleware.call(env_for(authorization: "Bearer my-token"))

      expect(headers["WWW-Authenticate"]).to include('error="invalid_token"')
      expect(headers["WWW-Authenticate"]).to match(/resource_metadata=".*\/.well-known\/oauth-authorization-server"/)
    end
  end

  context "when the Cognito JWKS cannot be fetched" do
    before { stub_request(:get, CognitoTokenHelper::TEST_JWKS_URL).to_return(status: 503) }

    it "returns 503 so the client retries instead of discarding its token" do
      status, = middleware.call(env_for(authorization: "Bearer #{signed_cognito_token}"))

      expect(status).to eq(503)
    end
  end

  context "without an Authorization header" do
    it "returns 401 with a WWW-Authenticate header outside development" do
      status, headers, = middleware.call(env_for)

      expect(status).to eq(401)
      expect(headers["WWW-Authenticate"]).to match(/Bearer resource_metadata=".*\/.well-known\/oauth-authorization-server"/)
      expect(headers["WWW-Authenticate"]).not_to include("error=")
    end

    it "passes through in development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      status, = middleware.call(env_for)

      expect(status).to eq(200)
    end
  end

  it "does not verify tokens in development" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

    status, = middleware.call(env_for(authorization: "Bearer my-token"))

    expect(status).to eq(200)
  end

  [
    "/healthcheckz",
    "/.well-known/oauth-protected-resource",
    "/.well-known/oauth-authorization-server",
    "/authorize",
    "/token",
    "/oauth/register"
  ].each do |path|
    it "passes #{path} through without a token" do
      status, = middleware.call(env_for(path: path))

      expect(status).to eq(200)
    end
  end
end
