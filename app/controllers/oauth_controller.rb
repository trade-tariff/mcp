# frozen_string_literal: true

class OauthController < ApplicationController
  # GET /.well-known/oauth-authorization-server
  #
  # OAuth 2.0 Authorization Server Metadata (RFC 8414). Claude uses this to
  # discover the token endpoint before presenting the connector credentials UI.
  def metadata
    render json: {
      issuer: request.base_url,
      token_endpoint: "#{request.base_url}/oauth/token",
      grant_types_supported: [ "client_credentials" ],
      token_endpoint_auth_methods_supported: [ "client_secret_post" ]
    }
  end

  HUB_TOKEN_URL = "https://auth.id.trade-tariff.service.gov.uk/oauth2/token"

  # POST /oauth/token
  #
  # Implements the client_credentials grant. Exchanges the caller's Hub
  # client_id + client_secret for a JWT from the identity provider, then
  # returns it so the MCP client can use it as a bearer token on subsequent
  # requests.
  def token
    unless params[:grant_type] == "client_credentials"
      return render json: { error: "unsupported_grant_type" }, status: :bad_request
    end

    client_id = params[:client_id].presence
    client_secret = params[:client_secret].presence

    unless client_id && client_secret
      return render json: { error: "invalid_client" }, status: :unauthorized
    end

    jwt = exchange_credentials(client_id, client_secret)

    if jwt
      render json: { access_token: jwt, token_type: "bearer" }
    else
      render json: { error: "invalid_client" }, status: :unauthorized
    end
  end

  private

  def exchange_credentials(client_id, client_secret)
    response = Faraday.post(HUB_TOKEN_URL) do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret,
        scope: "tariff/read"
      )
    end

    return nil unless response.status == 200

    body = JSON.parse(response.body)
    body["access_token"]
  rescue Faraday::Error, JSON::ParserError
    nil
  end
end
