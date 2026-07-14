# frozen_string_literal: true

class BearerTokenMiddleware
  UNAUTHENTICATED_PATHS = [
    "/healthcheckz",
    "/.well-known/oauth-protected-resource",
    "/.well-known/oauth-authorization-server",
    "/authorize",
    "/token",
    "/oauth/register"
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    if UNAUTHENTICATED_PATHS.exclude?(env["PATH_INFO"])
      token = extract_token(env["HTTP_AUTHORIZATION"])
      return unauthorized(env) unless token || Rails.env.development?

      CurrentRequest.bearer_token = token
      CurrentRequest.client_id = extract_client_id(token)
    end

    Rails.logger.tagged("client_id=#{CurrentRequest.client_id || "anonymous"}") do
      @app.call(env)
    end
  end

  private

  def extract_client_id(token)
    return nil unless token

    segments = token.split(".")
    return nil unless segments.length == 3

    payload = JSON.parse(Base64.urlsafe_decode64(segments[1]))
    payload["client_id"] || payload["sub"]
  rescue ArgumentError, JSON::ParserError
    nil
  end

  def extract_token(header)
    return nil if header.nil?

    if (match = header.match(/\ABearer (.+)\z/i))
      match[1].strip.presence
    else
      header.strip.presence
    end
  end

  def unauthorized(env)
    host = "#{env["rack.url_scheme"]}://#{env["HTTP_HOST"]}"
    metadata_url = "#{host}/.well-known/oauth-authorization-server"
    body = { error: "Unauthorized", message: "A Bearer token is required." }.to_json
    headers = {
      "Content-Type" => "application/json",
      "WWW-Authenticate" => %(Bearer resource_metadata="#{metadata_url}")
    }
    [ 401, headers, [ body ] ]
  end
end
