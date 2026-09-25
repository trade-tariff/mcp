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

      if Rails.env.development?
        # Local development runs without Cognito, so tokens are not checked.
        CurrentRequest.bearer_token = token
      else
        return unauthorized(env) unless token

        result = verifier.verify(token)
        return unauthorized(env, error: "invalid_token") if result.status == :invalid
        return service_unavailable if result.status == :unavailable

        CurrentRequest.bearer_token = token
        CurrentRequest.client_id = result.client_id
      end
    end

    client_id = CurrentRequest.client_id || "anonymous"
    Rails.logger.info("client_id=#{client_id} method=#{env["REQUEST_METHOD"]} path=#{env["PATH_INFO"]}")

    Rails.logger.tagged("client_id=#{client_id}") do
      @app.call(env)
    end
  end

  private

  def verifier
    CognitoTokenVerifier.new(
      user_pool_id: ENV.fetch("COGNITO_USER_POOL_ID"),
      region: ENV.fetch("COGNITO_REGION", "eu-west-2")
    )
  end

  def extract_token(header)
    return nil if header.nil?

    if (match = header.match(/\ABearer (.+)\z/i))
      match[1].strip.presence
    else
      header.strip.presence
    end
  end

  # Without an error, the challenge asks the client to start the OAuth flow.
  # With error="invalid_token" (RFC 6750), it tells the client to discard its
  # token and get a new one.
  def unauthorized(env, error: nil)
    host = "#{env["rack.url_scheme"]}://#{env["HTTP_HOST"]}"
    metadata_url = "#{host}/.well-known/oauth-authorization-server"
    challenge = %(Bearer resource_metadata="#{metadata_url}")
    challenge += %(, error="#{error}") if error
    message = error ? "The Bearer token is not valid." : "A Bearer token is required."
    body = { error: "Unauthorized", message: message }.to_json
    headers = {
      "Content-Type" => "application/json",
      "WWW-Authenticate" => challenge
    }
    [ 401, headers, [ body ] ]
  end

  def service_unavailable
    body = { error: "Service Unavailable", message: "Bearer tokens cannot be verified right now. Try again later." }.to_json
    [ 503, { "Content-Type" => "application/json", "Retry-After" => "5" }, [ body ] ]
  end
end
