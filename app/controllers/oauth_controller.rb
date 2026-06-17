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

  # POST /oauth/token
  #
  # Implements the client_credentials grant. The client_secret is the caller's
  # tariff API bearer token — we return it directly as the access_token so no
  # credential storage is needed on our side.
  def token
    unless params[:grant_type] == "client_credentials"
      return render json: { error: "unsupported_grant_type" }, status: :bad_request
    end

    secret = params[:client_secret].presence
    unless secret
      return render json: { error: "invalid_client" }, status: :unauthorized
    end

    render json: {
      access_token: secret,
      token_type: "bearer"
    }
  end
end
