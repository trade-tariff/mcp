# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth endpoints" do
  describe "GET /.well-known/oauth-protected-resource" do
    it "returns protected resource metadata without requiring a bearer token" do
      get "/.well-known/oauth-protected-resource"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["resource"]).to eq("http://www.example.com")
      expect(body["authorization_servers"]).to include("http://www.example.com")
    end
  end

  describe "GET /.well-known/oauth-authorization-server" do
    it "returns authorization server metadata without requiring a bearer token" do
      get "/.well-known/oauth-authorization-server"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["authorization_endpoint"]).to end_with("/authorize")
      expect(body["token_endpoint"]).to end_with("/token")
      expect(body["grant_types_supported"]).to include("authorization_code", "refresh_token")
      expect(body["code_challenge_methods_supported"]).to include("S256")
    end
  end

  describe "GET /authorize" do
    let(:code_verifier) { SecureRandom.urlsafe_base64(43) }
    let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }
    let(:valid_params) do
      {
        response_type: "code",
        client_id: "my-client-id",
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        code_challenge: code_challenge,
        code_challenge_method: "S256",
        state: "random-state"
      }
    end

    it "redirects to the redirect_uri with a code and state" do
      get "/authorize", params: valid_params

      expect(response).to have_http_status(:redirect)
      location = URI.parse(response.headers["Location"])
      query = URI.decode_www_form(location.query).to_h
      expect(query["code"]).to be_present
      expect(query["state"]).to eq("random-state")
    end

    it "stores the code in the cache for later token exchange" do
      get "/authorize", params: valid_params

      location = URI.parse(response.headers["Location"])
      code = URI.decode_www_form(location.query).to_h["code"]
      stored = Rails.cache.read("oauth_code:#{code}")
      expect(stored[:client_id]).to eq("my-client-id")
      expect(stored[:code_challenge]).to eq(code_challenge)
    end

    it "returns 400 when response_type is not code" do
      get "/authorize", params: valid_params.merge(response_type: "token")
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when code_challenge_method is not S256" do
      get "/authorize", params: valid_params.merge(code_challenge_method: "plain")
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when required params are missing" do
      get "/authorize", params: valid_params.except(:code_challenge)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /token" do
    let(:hub_token_url) { OauthController::HUB_TOKEN_URL }
    let(:jwt) { "a.b.c" }
    let(:code_verifier) { SecureRandom.urlsafe_base64(43) }
    let(:code_challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false) }
    let(:code) { "test-code" }

    before do
      Rails.cache.write("oauth_code:#{code}", { client_id: "my-client-id", code_challenge: code_challenge })
    end

    context "with a valid code and credentials" do
      before do
        stub_request(:post, hub_token_url)
          .to_return(status: 200, body: { access_token: jwt, expires_in: 3600 }.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns the JWT as the access_token" do
        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "my-client-secret",
          code_verifier: code_verifier
        }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["access_token"]).to eq(jwt)
        expect(body["token_type"]).to eq("bearer")
      end

      it "returns expires_in from Cognito so the client knows when to refresh" do
        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "my-client-secret",
          code_verifier: code_verifier
        }

        expect(JSON.parse(response.body)["expires_in"]).to eq(3600)
      end

      it "returns a refresh_token that does not show the client_secret" do
        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "my-client-secret",
          code_verifier: code_verifier
        }

        refresh_token = JSON.parse(response.body)["refresh_token"]
        expect(refresh_token).to be_present
        expect(refresh_token).not_to include("my-client-secret")
        expect(Base64.decode64(refresh_token.split("--").first)).not_to include("my-client-secret")
      end

      it "consumes the code so it cannot be reused" do
        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "my-client-secret",
          code_verifier: code_verifier
        }

        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "my-client-secret",
          code_verifier: code_verifier
        }

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
      end
    end

    it "returns invalid_grant when the code_verifier does not match" do
      post "/token", params: {
        grant_type: "authorization_code",
        code: code,
        client_id: "my-client-id",
        client_secret: "my-client-secret",
        code_verifier: "wrong-verifier"
      }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "returns invalid_grant when the client_id does not match" do
      post "/token", params: {
        grant_type: "authorization_code",
        code: code,
        client_id: "wrong-client-id",
        client_secret: "my-client-secret",
        code_verifier: code_verifier
      }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    context "when the Hub token request times out" do
      before do
        stub_request(:post, hub_token_url).to_timeout
      end

      it "returns invalid_client rather than hanging" do
        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "my-client-secret",
          code_verifier: code_verifier
        }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
      end
    end

    context "when Hub rejects the credentials" do
      before do
        stub_request(:post, hub_token_url).to_return(status: 401, body: { error: "invalid_client" }.to_json)
      end

      it "returns 401" do
        post "/token", params: {
          grant_type: "authorization_code",
          code: code,
          client_id: "my-client-id",
          client_secret: "bad-secret",
          code_verifier: code_verifier
        }

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
      end
    end

    it "returns 400 for an unsupported grant_type" do
      post "/token", params: { grant_type: "client_credentials", client_id: "x", client_secret: "y" }
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("unsupported_grant_type")
    end

    it "returns 400 when required params are missing" do
      post "/token", params: { grant_type: "authorization_code", code: code, client_id: "my-client-id" }
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
    end
  end

  describe "POST /token with grant_type=refresh_token" do
    let(:hub_token_url) { OauthController::HUB_TOKEN_URL }
    let(:refresh_token) { OauthRefreshToken.issue(client_id: "my-client-id", client_secret: "my-client-secret") }

    def refresh(params = {})
      post "/token", params: { grant_type: "refresh_token", refresh_token: refresh_token }.merge(params)
    end

    context "when Cognito accepts the stored credentials" do
      before do
        stub_request(:post, hub_token_url)
          .with(body: hash_including("grant_type" => "client_credentials", "client_id" => "my-client-id",
                                     "client_secret" => "my-client-secret", "scope" => "tariff/read"))
          .to_return(status: 200, body: { access_token: "new.access.token", expires_in: 3600 }.to_json,
                     headers: { "Content-Type" => "application/json" })
      end

      it "returns a new access_token" do
        refresh

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["access_token"]).to eq("new.access.token")
        expect(body["token_type"]).to eq("bearer")
        expect(body["expires_in"]).to eq(3600)
      end

      it "returns a new refresh_token that can be used again" do
        refresh
        next_refresh_token = JSON.parse(response.body)["refresh_token"]

        post "/token", params: { grant_type: "refresh_token", refresh_token: next_refresh_token }

        expect(response).to have_http_status(:ok)
      end

      it "accepts a client_id that matches the refresh token" do
        refresh(client_id: "my-client-id", client_secret: "my-client-secret")

        expect(response).to have_http_status(:ok)
      end

      it "accepts a refresh token up to 30 days old" do
        token = refresh_token

        travel_to(29.days.from_now) do
          post "/token", params: { grant_type: "refresh_token", refresh_token: token }
        end

        expect(response).to have_http_status(:ok)
      end
    end

    it "returns invalid_grant when the client_id does not match the refresh token" do
      refresh(client_id: "other-client-id")

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "returns invalid_grant for a refresh token that has been changed" do
      post "/token", params: { grant_type: "refresh_token", refresh_token: "#{refresh_token}x" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "returns invalid_grant for a string that is not a refresh token" do
      post "/token", params: { grant_type: "refresh_token", refresh_token: "not-a-refresh-token" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "returns invalid_grant for a refresh token older than 30 days" do
      token = refresh_token

      travel_to(31.days.from_now) do
        post "/token", params: { grant_type: "refresh_token", refresh_token: token }
      end

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "returns invalid_request when refresh_token is missing" do
      post "/token", params: { grant_type: "refresh_token" }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
    end

    context "when Cognito rejects the credentials because the client was deleted in the hub" do
      before do
        stub_request(:post, hub_token_url).to_return(status: 400, body: { error: "invalid_client" }.to_json)
      end

      it "returns invalid_grant so the client starts the OAuth flow again" do
        refresh

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
      end
    end

    context "when the Cognito token request times out" do
      before { stub_request(:post, hub_token_url).to_timeout }

      it "returns 503 so the client keeps its refresh token and tries again" do
        refresh

        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)["error"]).to eq("temporarily_unavailable")
      end
    end
  end
end
