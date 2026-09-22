# frozen_string_literal: true

Rails.application.config.after_initialize do
  resources = [
    ClassificationWorkflowResource,
    GriRulesResource
  ].freeze

  server = MCP::Server.new(
    name: "trade-tariff",
    version: "0.1.0",
    instructions: <<~INSTRUCTIONS.strip,
      Never state, imply, or fill in a commodity code, duty rate, quota balance, figure, or any other
      value that a trade-tariff tool call did not itself return. If a tool returns no data, an empty
      result, or an explicit notice saying something was not found, treat that as "unknown" — say so
      plainly and suggest the next tool to try — rather than guessing, estimating, or reconstructing
      the answer from general knowledge. Relative match bands and calculation notes returned by these
      tools describe real limitations in the underlying data; do not round them up or omit them when
      reporting results to the user. A relative match band compares results within one search only. It
      is not a probability, and it is never comparable between searches. When the user asks about
      several products at once, classify them one at a time and finish one product before you start
      the next.
    INSTRUCTIONS
    tools: [
      ListSectionsTool,
      ClassificationSearchTool,
      NoteMentionsTool,
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
