Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  mcp_transport = nil
  mcp_app = lambda do |env|
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
    mcp_transport.call(env)
  end

  mount mcp_app, at: "/mcp"
end
