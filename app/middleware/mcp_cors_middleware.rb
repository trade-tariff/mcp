# frozen_string_literal: true

# Handles CORS before Rails routing. Rails does not route OPTIONS requests to
# mounted Rack apps, so preflight must be intercepted here. CORS headers are
# added to all responses except the health check.
class McpCorsMiddleware
  CORS_HEADERS = {
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers" => "Authorization, Content-Type, Accept, Mcp-Session-Id, Mcp-Protocol-Version",
    "Access-Control-Expose-Headers" => "Mcp-Session-Id",
    "Access-Control-Max-Age" => "86400"
  }.freeze

  HEALTH_PATH = "/healthcheckz"

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"]

    return [ 200, CORS_HEADERS.dup, [] ] if env["REQUEST_METHOD"] == "OPTIONS" && path != HEALTH_PATH

    status, headers, body = @app.call(env)

    headers = headers.merge(CORS_HEADERS) unless path == HEALTH_PATH

    [ status, headers, body ]
  end
end
