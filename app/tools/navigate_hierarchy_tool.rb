# frozen_string_literal: true

class NavigateHierarchyTool < ApplicationTool
  tool_name "navigate_hierarchy"
  description "Look up a goods nomenclature entry by a 4-10 digit code. Returns the item and its position in the tariff hierarchy."

  input_schema(
    properties: {
      code: {
        type: "string",
        description: "4 to 10-digit goods nomenclature code, e.g. '0101' or '0101210000'.",
        pattern: "\\A\\d{4,10}\\z"
      },
      service: {
        type: "string",
        description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
      }
    },
    required: [ "code" ]
  )

  def self.call(code:, service: nil, server_context: nil)
    unless code.match?(/\A\d{4,10}\z/)
      return MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid code: must be 4 to 10 digits, got '#{code}'" } ],
        error: true
      )
    end

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/goods_nomenclatures/#{code}")) }
  end
end
