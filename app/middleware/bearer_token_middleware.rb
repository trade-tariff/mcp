# frozen_string_literal: true

class BearerTokenMiddleware
  HEALTH_PATH = "/up"

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["PATH_INFO"] != HEALTH_PATH
      token = extract_token(env["HTTP_AUTHORIZATION"])
      return unauthorized unless token

      CurrentRequest.bearer_token = token
    end

    @app.call(env)
  end

  private

  def extract_token(header)
    return nil if header.nil?

    match = header.match(/\ABearer (.+)\z/i)
    match&.[](1)&.strip.presence
  end

  def unauthorized
    body = { error: "Unauthorized", message: "A Bearer token is required." }.to_json
    [ 401, { "Content-Type" => "application/json" }, [ body ] ]
  end
end
