# frozen_string_literal: true

class ListSectionsTool < ApplicationTool
  tool_name "list_sections"
  description "List all sections of the Trade Tariff. Sections are the top-level groupings of goods."

  input_schema(
    properties: {
      service: {
        type: "string",
        description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
      }
    },
  )

  def self.call(service: nil, server_context: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/sections")) }
  end
end
