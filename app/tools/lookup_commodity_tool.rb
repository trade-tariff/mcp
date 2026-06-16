# frozen_string_literal: true

class LookupCommodityTool < ApplicationTool
  tool_name "lookup_commodity"
  description "Look up a commodity by its 10-digit commodity code. Returns description, measures, duties, and other tariff details."

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "\\A\\d{10}\\z"
      },
      service: {
        type: "string",
        description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
      }
    },
    required: [ "commodity_code" ]
  )

  def self.call(commodity_code:, service: nil, server_context: nil)
    unless commodity_code.match?(/\A\d{10}\z/)
      return MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid commodity_code: must be exactly 10 digits, got '#{commodity_code}'" } ],
        error: true
      )
    end

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/commodities/#{commodity_code}")) }
  end
end
