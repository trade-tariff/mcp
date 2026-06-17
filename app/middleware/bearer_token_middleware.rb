# frozen_string_literal: true

class BearerTokenMiddleware
  UNAUTHENTICATED_PATHS = [
    "/healthcheckz",
    "/.well-known/oauth-authorization-server",
    "/oauth/token"
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    if UNAUTHENTICATED_PATHS.exclude?(env["PATH_INFO"])
      token = extract_token(env["HTTP_AUTHORIZATION"])
      return unauthorized unless token || Rails.env.development?

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

  def unauthorized
    body = { error: "Unauthorized", message: "A Bearer token is required." }.to_json
    [ 401, { "Content-Type" => "application/json" }, [ body ] ]
  end
end
