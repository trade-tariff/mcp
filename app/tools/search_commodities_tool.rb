# frozen_string_literal: true

class SearchCommoditiesTool < ApplicationTool
  tool_name "search_commodities"
  description "Search the Trade Tariff by keyword. Returns matching commodities, headings, and chapters."

  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Search term, e.g. 'horses' or 'bicycle parts'."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "query" ]
  )

  def self.call(query:, service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/search", params: { "q" => query }, as_of: validity_date)) }
  end
end
