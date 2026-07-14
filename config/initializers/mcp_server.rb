# frozen_string_literal: true

Rails.application.config.after_initialize do
  resources = [
    ClassificationWorkflowResource,
    GriRulesResource
  ].freeze

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
    resources: resources.map(&:resource)
  )

  server.resources_read_handler do |params|
    resource_class = resources.find { |r| r.resource.uri == params[:uri] }
    raise MCP::Server::ResourceNotFoundError.new(params[:uri], params) unless resource_class

    [ { uri: params[:uri], mimeType: "text/markdown", text: resource_class.content } ]
  end

  Rails.application.config.mcp_transport =
    MCP::Server::Transports::StreamableHTTPTransport.new(
      server,
      stateless: true,
      enable_json_response: true,
      allowed_hosts: [
        "mcp.trade-tariff.service.gov.uk",
        "mcp.staging.trade-tariff.service.gov.uk",
        "mcp.dev.trade-tariff.service.gov.uk",
        "localhost",
        "localhost:3000"
      ]
    )
end
