# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth endpoints" do
  describe "GET /.well-known/oauth-authorization-server" do
    it "returns the OAuth server metadata without requiring a bearer token" do
      get "/.well-known/oauth-authorization-server"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token_endpoint"]).to end_with("/oauth/token")
      expect(body["grant_types_supported"]).to include("client_credentials")
    end
  end

  describe "POST /oauth/token" do
    it "returns the client_secret as the access_token for a client_credentials grant" do
      post "/oauth/token", params: { grant_type: "client_credentials", client_secret: "my-api-token" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["access_token"]).to eq("my-api-token")
      expect(body["token_type"]).to eq("bearer")
    end

    it "returns 400 for an unsupported grant_type" do
      post "/oauth/token", params: { grant_type: "authorization_code", client_secret: "my-api-token" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("unsupported_grant_type")
    end

    it "returns 401 when client_secret is missing" do
      post "/oauth/token", params: { grant_type: "client_credentials" }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
    end
  end
end
