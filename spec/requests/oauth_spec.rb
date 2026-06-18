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
    let(:hub_token_url) { OauthController::HUB_TOKEN_URL }
    let(:jwt) { "a.b.c" }

    context "with valid client_id and client_secret" do
      before do
        stub_request(:post, hub_token_url)
          .to_return(status: 200, body: { access_token: jwt }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "exchanges credentials with Hub and returns the JWT as the access_token" do
        post "/oauth/token", params: { grant_type: "client_credentials", client_id: "my-client-id", client_secret: "my-client-secret" }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["access_token"]).to eq(jwt)
        expect(body["token_type"]).to eq("bearer")
      end

      it "sends client_id, client_secret, and scope to Hub" do
        post "/oauth/token", params: { grant_type: "client_credentials", client_id: "my-client-id", client_secret: "my-client-secret" }

        expect(WebMock).to have_requested(:post, hub_token_url)
          .with(body: hash_including("client_id" => "my-client-id", "client_secret" => "my-client-secret", "scope" => "tariff/read"))
      end
    end

    context "when Hub rejects the credentials" do
      before do
        stub_request(:post, hub_token_url).to_return(status: 401, body: { error: "invalid_client" }.to_json)
      end

      it "returns 401" do
        post "/oauth/token", params: { grant_type: "client_credentials", client_id: "bad-id", client_secret: "bad-secret" }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
      end
    end

    it "returns 400 for an unsupported grant_type" do
      post "/oauth/token", params: { grant_type: "authorization_code", client_id: "x", client_secret: "y" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("unsupported_grant_type")
    end

    it "returns 401 when client_id or client_secret is missing" do
      post "/oauth/token", params: { grant_type: "client_credentials", client_secret: "my-client-secret" }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
    end
  end
end
