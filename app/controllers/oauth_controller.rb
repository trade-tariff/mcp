# frozen_string_literal: true

class OauthController < ApplicationController
  HUB_TOKEN_URL = ENV.fetch("HUB_TOKEN_URL", "https://auth.id.trade-tariff.service.gov.uk/oauth2/token")
  DEVHUB_URL = ENV.fetch("DEVHUB_URL", "https://hub.trade-tariff.service.gov.uk")

  # Codes are single-use and short-lived.
  AUTH_CODE_TTL = 5.minutes

  # Result of a client_credentials exchange with Hub:
  #   :issued      - Cognito gave an access token
  #   :rejected    - Cognito refused the credentials
  #   :unavailable - Cognito could not be reached or gave an unreadable reply
  HubTokenResult = Data.define(:status, :access_token, :expires_in)

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
      grant_types_supported: [ "authorization_code", "refresh_token" ],
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
  # Token endpoint for the authorization_code and refresh_token grants.
  # Both exchange a client_id + client_secret with Hub (client_credentials)
  # to get a Cognito access token, which lasts about an hour.
  def token
    case params[:grant_type]
    when "authorization_code"
      authorization_code_grant
    when "refresh_token"
      refresh_token_grant
    else
      render json: { error: "unsupported_grant_type" }, status: :bad_request
    end
  end

  private

  # Verifies the PKCE code_verifier against the stored code_challenge, then
  # exchanges the credentials the client sent.
  def authorization_code_grant
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

    result = exchange_credentials(client_id, client_secret)
    return render json: { error: "invalid_client" }, status: :unauthorized unless result.status == :issued

    render_token_response(result, client_id, client_secret)
  end

  # Decrypts the credentials held in the refresh token and exchanges them
  # again. A rejected exchange is invalid_grant, so the client starts the
  # OAuth flow again. An outage is a 503, so the client keeps its refresh
  # token and tries later.
  def refresh_token_grant
    refresh_token = params[:refresh_token].presence
    return render json: { error: "invalid_request" }, status: :bad_request unless refresh_token

    credentials = OauthRefreshToken.read(refresh_token)
    return render json: { error: "invalid_grant" }, status: :bad_request unless credentials

    if params[:client_id].present? && params[:client_id] != credentials.client_id
      return render json: { error: "invalid_grant" }, status: :bad_request
    end

    result = exchange_credentials(credentials.client_id, credentials.client_secret)
    case result.status
    when :issued
      render_token_response(result, credentials.client_id, credentials.client_secret)
    when :rejected
      render json: { error: "invalid_grant" }, status: :bad_request
    else
      render json: { error: "temporarily_unavailable" }, status: :service_unavailable
    end
  end

  def render_token_response(result, client_id, client_secret)
    render json: {
      access_token: result.access_token,
      token_type: "bearer",
      expires_in: result.expires_in,
      refresh_token: OauthRefreshToken.issue(client_id: client_id, client_secret: client_secret)
    }.compact
  end

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

    if response.status >= 500
      Rails.logger.warn("Hub token exchange unavailable: status=#{response.status}")
      return HubTokenResult.new(status: :unavailable, access_token: nil, expires_in: nil)
    end

    unless response.status == 200
      Rails.logger.warn("Hub token exchange failed: status=#{response.status} body=#{response.body.truncate(500)}")
      return HubTokenResult.new(status: :rejected, access_token: nil, expires_in: nil)
    end

    body = JSON.parse(response.body)
    if body["access_token"].blank?
      Rails.logger.warn("Hub token exchange response had no access_token")
      return HubTokenResult.new(status: :unavailable, access_token: nil, expires_in: nil)
    end

    HubTokenResult.new(status: :issued, access_token: body["access_token"], expires_in: body["expires_in"])
  rescue Faraday::Error => e
    Rails.logger.warn("Hub token exchange error: #{e.class} #{e.message}")
    HubTokenResult.new(status: :unavailable, access_token: nil, expires_in: nil)
  rescue JSON::ParserError => e
    Rails.logger.warn("Hub token exchange unparseable response: #{e.message}")
    HubTokenResult.new(status: :unavailable, access_token: nil, expires_in: nil)
  end

  def render_error(error, description)
    render json: { error: error, error_description: description }, status: :bad_request
  end
end
