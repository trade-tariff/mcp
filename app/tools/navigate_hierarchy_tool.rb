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
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "code" ]
  )

  def self.call(code:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(code, /\A\d{4,10}\z/, "code") || validate_date(validity_date)
    return error if error

    padded = code.ljust(10, "0")
    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/goods_nomenclatures/#{padded}", as_of: validity_date)) }
  end
end
