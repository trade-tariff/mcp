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
    end

    @app.call(env)
  end

  private

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
