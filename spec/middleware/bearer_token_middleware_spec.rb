# frozen_string_literal: true

require "rails_helper"

RSpec.describe BearerTokenMiddleware do
  let(:inner_app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }
  let(:middleware) { described_class.new(inner_app) }

  def env_for(path: "/", authorization: nil)
    env = Rack::MockRequest.env_for(path)
    env["HTTP_AUTHORIZATION"] = authorization if authorization
    env
  end

  def jwt_with_claims(claims)
    payload = Base64.urlsafe_encode64(claims.to_json, padding: false)
    "header.#{payload}.signature"
  end

  it "accepts a token with the Bearer prefix" do
    middleware.call(env_for(authorization: "Bearer my-token"))
    expect(CurrentRequest.bearer_token).to eq("my-token")
  end

  it "extracts client_id from a JWT with a client_id claim" do
    token = jwt_with_claims("client_id" => "my-client", "sub" => "my-subject")
    middleware.call(env_for(authorization: "Bearer #{token}"))
    expect(CurrentRequest.client_id).to eq("my-client")
  end

  it "falls back to sub when client_id claim is absent" do
    token = jwt_with_claims("sub" => "my-subject")
    middleware.call(env_for(authorization: "Bearer #{token}"))
    expect(CurrentRequest.client_id).to eq("my-subject")
  end

  it "sets client_id to nil for a non-JWT token" do
    middleware.call(env_for(authorization: "Bearer not-a-jwt"))
    expect(CurrentRequest.client_id).to be_nil
  end

  it "tags log output with the client_id when a JWT is present" do
    token = jwt_with_claims("client_id" => "tagged-client")
    tagged_messages = []
    allow(Rails.logger).to receive(:tagged) { |tag, &block|
      tagged_messages << tag
      block.call
    }
    middleware.call(env_for(authorization: "Bearer #{token}"))
    expect(tagged_messages).to include("tagged-client")
  end

  it "accepts a raw token without the Bearer prefix" do
    middleware.call(env_for(authorization: "my-token"))
    expect(CurrentRequest.bearer_token).to eq("my-token")
  end

  it "returns 401 with a WWW-Authenticate header when no Authorization header is present outside development" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    status, headers, = middleware.call(env_for)
    expect(status).to eq(401)
    expect(headers["WWW-Authenticate"]).to match(/Bearer resource_metadata=".*\/.well-known\/oauth-authorization-server"/)
  end

  it "passes through unauthenticated paths without a token" do
    status, = middleware.call(env_for(path: "/healthcheckz"))
    expect(status).to eq(200)
  end

  it "passes through the OAuth protected resource path without a token" do
    status, = middleware.call(env_for(path: "/.well-known/oauth-protected-resource"))
    expect(status).to eq(200)
  end

  it "passes through the OAuth authorization server metadata path without a token" do
    status, = middleware.call(env_for(path: "/.well-known/oauth-authorization-server"))
    expect(status).to eq(200)
  end

  it "passes through the OAuth authorize path without a token" do
    status, = middleware.call(env_for(path: "/authorize"))
    expect(status).to eq(200)
  end

  it "passes through the OAuth token path without a token" do
    status, = middleware.call(env_for(path: "/token"))
    expect(status).to eq(200)
  end
end
