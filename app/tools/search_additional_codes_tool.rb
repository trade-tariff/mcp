# frozen_string_literal: true

class SearchAdditionalCodesTool < ApplicationTool
  tool_name "search_additional_codes"
  description "Search additional codes (e.g. Meursing codes for agricultural goods with variable duties). Use this when a commodity measure requires an additional code to calculate the correct duty."

  input_schema(
    properties: {
      description: {
        type: "string",
        description: "Filter by additional code description (partial match)."
      },
      type: {
        type: "string",
        description: "Filter by additional code type ID."
      },
      code: {
        type: "string",
        description: "Filter by additional code value."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    }
  )

  def self.call(description: nil, type: nil, code: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date)
    return error if error

    params = {}
    params["description"] = description if description
    params["type"] = type if type
    params["code"] = code if code

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/additional_codes/search", params: params, as_of: validity_date)) }
  end
end
