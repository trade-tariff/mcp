# frozen_string_literal: true

require "cgi"

class SearchCommoditiesTool < ApplicationTool
  tool_name "search_commodities"
  description "Search the Trade Tariff by keyword. Returns matching commodities, headings, and chapters."

  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Search term, e.g. 'horses' or 'bicycle parts'."
      },
      service: {
        type: "string",
        description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
      }
    },
    required: ["query"]
  )

  def self.call(query:, service: nil, server_context: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/search?q=#{CGI.escape(query)}")) }
  end
end
