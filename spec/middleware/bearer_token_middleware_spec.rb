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

  it "accepts a token with the Bearer prefix" do
    middleware.call(env_for(authorization: "Bearer my-token"))
    expect(CurrentRequest.bearer_token).to eq("my-token")
  end

  it "accepts a raw token without the Bearer prefix" do
    middleware.call(env_for(authorization: "my-token"))
    expect(CurrentRequest.bearer_token).to eq("my-token")
  end

  it "returns 401 when no Authorization header is present outside development" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    status, = middleware.call(env_for)
    expect(status).to eq(401)
  end

  it "passes through unauthenticated paths without a token" do
    status, = middleware.call(env_for(path: "/up"))
    expect(status).to eq(200)
  end

  it "passes through the OAuth metadata path without a token" do
    status, = middleware.call(env_for(path: "/.well-known/oauth-authorization-server"))
    expect(status).to eq(200)
  end

  it "passes through the OAuth token path without a token" do
    status, = middleware.call(env_for(path: "/oauth/token"))
    expect(status).to eq(200)
  end
end
