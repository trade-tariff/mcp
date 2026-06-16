# frozen_string_literal: true

# fast-mcp handles CORS preflight for /mcp/sse but not /mcp/messages.
# This middleware intercepts OPTIONS requests to MCP paths and returns
# the correct CORS headers so browser-based MCP clients (e.g. MCP Inspector)
# can complete the preflight and proceed with the actual request.
class McpCorsMiddleware
  MCP_PATH_PREFIX = "/mcp"

  CORS_HEADERS = {
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type, Accept",
    "Access-Control-Max-Age" => "86400"
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["REQUEST_METHOD"] == "OPTIONS" && env["PATH_INFO"].start_with?(MCP_PATH_PREFIX)
      return [200, CORS_HEADERS, []]
    end

    @app.call(env)
  end
end
