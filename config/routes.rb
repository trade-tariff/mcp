Rails.application.routes.draw do
  get "healthcheckz" => "rails/health#show", as: :rails_health_check

  get ".well-known/oauth-protected-resource" => "oauth#protected_resource"
  get ".well-known/oauth-authorization-server" => "oauth#metadata"
  get "oauth/authorize" => "oauth#authorize"
  post "oauth/token" => "oauth#token"

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
          NavigateHierarchyTool,
          ListExchangeRatesTool,
          ListGeographicalAreasTool,
          SearchQuotasTool,
          SearchAdditionalCodesTool,
          ListCertificateTypesTool,
          RulesOfOriginTool
        ]
      ),
      stateless: true,
      enable_json_response: true
    )
    mcp_transport.call(env)
  end

  mount mcp_app, at: "/"
end
