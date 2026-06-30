Rails.application.routes.draw do
  get "healthcheckz" => "rails/health#show", as: :rails_health_check

  get ".well-known/oauth-protected-resource" => "oauth#protected_resource"
  get ".well-known/oauth-authorization-server" => "oauth#metadata"
  get "authorize" => "oauth#authorize"
  post "token" => "oauth#token"
  post "oauth/register" => "oauth#register"

  RESOURCES = [
    ClassificationWorkflowResource,
    GriRulesResource
  ].freeze

  mcp_transport = nil
  mcp_app = lambda do |env|
    mcp_transport ||= begin
      server = MCP::Server.new(
        name: "trade-tariff",
        version: "0.1.0",
        tools: [
          ListSectionsTool,
          ClassificationSearchTool,
          NoteMentionsTool,
          ShowChapterTool,
          ShowHeadingTool,
          LookupCommodityTool,
          NavigateHierarchyTool,
          ListExchangeRatesTool,
          ListGeographicalAreasTool,
          SearchQuotasTool,
          SearchAdditionalCodesTool,
          ListCertificateTypesTool,
          RulesOfOriginTool,
          DutyVatCalculatorTool,
          FullTextSearchTool,
          CommodityHistoryDiffTool,
          CommodityMeasuresTool,
          CommodityQuotasTool
        ],
        resources: RESOURCES.map(&:resource)
      )

      server.resources_read_handler do |params|
        resource_class = RESOURCES.find { |r| r.resource.uri == params[:uri] }
        raise MCP::Server::ResourceNotFoundError.new(params[:uri], params) unless resource_class

        [ { uri: params[:uri], mimeType: "text/markdown", text: resource_class.content } ]
      end

      MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true, enable_json_response: true)
    end
    mcp_transport.call(env)
  end

  mount mcp_app, at: "/"
end
