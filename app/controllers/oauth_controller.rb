# frozen_string_literal: true

class OauthController < ApplicationController
  HUB_TOKEN_URL = ENV.fetch("HUB_TOKEN_URL", "https://auth.id.trade-tariff.service.gov.uk/oauth2/token")
  DEVHUB_URL = ENV.fetch("DEVHUB_URL", "https://hub.trade-tariff.service.gov.uk")

  # Codes are single-use and short-lived.
  AUTH_CODE_TTL = 5.minutes

  # GET /.well-known/oauth-protected-resource
  #
  # OAuth Protected Resource Metadata (RFC 9728). Clients fetch this after
  # receiving a WWW-Authenticate: Bearer resource_metadata="..." challenge.
  # Points back at this server as the authorization server so clients then
  # fetch /.well-known/oauth-authorization-server.
  def protected_resource
    render json: {
      resource: request.base_url,
      authorization_servers: [ request.base_url ]
    }
  end

  # GET /.well-known/oauth-authorization-server
  #
  # OAuth 2.0 Authorization Server Metadata (RFC 8414). Advertises the
  # authorization and token endpoints so clients know where to go.
  def metadata
    render json: {
      issuer: request.base_url,
      authorization_endpoint: "#{request.base_url}/authorize",
      token_endpoint: "#{request.base_url}/token",
      grant_types_supported: [ "authorization_code" ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: [ "client_secret_post" ]
    }
  end

  # POST /oauth/register
  #
  # Dynamic Client Registration (RFC 7591). We don't support automated
  # registration — clients must obtain credentials from the developer portal
  # and configure them in their MCP client manually.
  def register
    render json: {
      error: "invalid_client_metadata",
      error_description: "Automatic client registration is not supported. " \
                         "Please register at #{DEVHUB_URL} to obtain a client_id and client_secret, " \
                         "then configure them in your MCP client."
    }, status: :bad_request
  end

  # GET /oauth/authorize
  #
  # Authorization endpoint for the Authorization Code + PKCE flow. Validates
  # the request, generates a short-lived code, and immediately redirects back
  # to the client — no login UI is needed because the client_secret proves
  # identity at the token exchange step.
  def authorize
    return render_error("invalid_request", "response_type must be 'code'") unless params[:response_type] == "code"
    return render_error("invalid_request", "client_id is required") unless params[:client_id].present?
    return render_error("invalid_request", "redirect_uri is required") unless params[:redirect_uri].present?
    return render_error("invalid_request", "code_challenge is required") unless params[:code_challenge].present?
    return render_error("invalid_request", "code_challenge_method must be 'S256'") unless params[:code_challenge_method] == "S256"

    code = SecureRandom.urlsafe_base64(32)

    Rails.cache.write("oauth_code:#{code}", {
      client_id: params[:client_id],
      code_challenge: params[:code_challenge]
    }, expires_in: AUTH_CODE_TTL)

    callback_uri = URI.parse(params[:redirect_uri])
    callback_params = { code: code }
    callback_params[:state] = params[:state] if params[:state].present?
    callback_uri.query = URI.encode_www_form(callback_params)

    redirect_to callback_uri.to_s, allow_other_host: true
  end

  # POST /oauth/token
  #
  # Token endpoint. Handles the authorization_code grant: verifies the PKCE
  # code_verifier against the stored code_challenge, then exchanges the
  # client_id + client_secret with Hub (client_credentials) to obtain a JWT.
  def token
    unless params[:grant_type] == "authorization_code"
      return render json: { error: "unsupported_grant_type" }, status: :bad_request
    end

    code = params[:code].presence
    client_id = params[:client_id].presence
    client_secret = params[:client_secret].presence
    code_verifier = params[:code_verifier].presence

    unless code && client_id && client_secret && code_verifier
      return render json: { error: "invalid_request" }, status: :bad_request
    end

    stored = Rails.cache.read("oauth_code:#{code}")
    Rails.cache.delete("oauth_code:#{code}")
    return render json: { error: "invalid_grant" }, status: :bad_request unless stored
    return render json: { error: "invalid_grant" }, status: :bad_request unless stored[:client_id] == client_id
    return render json: { error: "invalid_grant" }, status: :bad_request unless pkce_valid?(code_verifier, stored[:code_challenge])

    jwt = exchange_credentials(client_id, client_secret)
    if jwt
      render json: { access_token: jwt, token_type: "bearer" }
    else
      render json: { error: "invalid_client" }, status: :unauthorized
    end
  end

  private

  def pkce_valid?(code_verifier, code_challenge)
    digest = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(digest, code_challenge)
  end

  def exchange_credentials(client_id, client_secret)
    response = Faraday.post(HUB_TOKEN_URL) do |req|
      req.options.open_timeout = 5
      req.options.timeout = 10
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret,
        scope: "tariff/read"
      )
    end

    unless response.status == 200
      Rails.logger.warn("Hub token exchange failed: status=#{response.status} body=#{response.body.truncate(500)}")
      return nil
    end

    body = JSON.parse(response.body)
    body["access_token"]
  rescue Faraday::Error => e
    Rails.logger.warn("Hub token exchange error: #{e.class} #{e.message}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.warn("Hub token exchange unparseable response: #{e.message}")
    nil
  end

  def render_error(error, description)
    render json: { error: error, error_description: description }, status: :bad_request
  end
end
