Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  cors_headers = {
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type, Accept, Mcp-Session-Id",
    "Access-Control-Max-Age" => "86400"
  }.freeze

  mcp_transport = nil
  mcp_app = lambda do |env|
    if env["REQUEST_METHOD"] == "OPTIONS"
      return [200, cors_headers, []]
    end

    mcp_transport ||= MCP::Server::Transports::StreamableHTTPTransport.new(
      MCP::Server.new(
        name: "trade-tariff",
        version: "0.1.0",
        tools: [
          ListSectionsTool,
          ShowChapterTool,
          ShowHeadingTool,
          LookupCommodityTool,
          SearchCommoditiesTool,
          NavigateHierarchyTool
        ]
      ),
      stateless: true
    )

    status, headers, body = mcp_transport.call(env)
    [status, headers.merge(cors_headers), body]
  end

  mount mcp_app, at: "/mcp"
end
