# frozen_string_literal: true

# Handles CORS for the /mcp endpoint before Rails routing.
# Rails does not route OPTIONS requests to mounted Rack apps, so preflight
# must be intercepted here. We also inject CORS headers into every /mcp
# response so browser-based clients (e.g. MCP Inspector) can read them.
class McpCorsMiddleware
  CORS_HEADERS = {
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type, Accept, Mcp-Session-Id, Mcp-Protocol-Version",
    "Access-Control-Expose-Headers" => "Mcp-Session-Id",
    "Access-Control-Max-Age" => "86400"
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["REQUEST_METHOD"] == "OPTIONS" && env["PATH_INFO"].start_with?("/mcp")
      return [200, CORS_HEADERS.dup, []]
    end

    status, headers, body = @app.call(env)

    if env["PATH_INFO"].start_with?("/mcp")
      headers = headers.merge(CORS_HEADERS)
    end

    [status, headers, body]
  end
end
