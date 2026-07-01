# frozen_string_literal: true

class NavigateHierarchyTool < ApplicationTool
  tool_name "navigate_hierarchy"
  description "Use after classification_search, show_heading, or when you already have a known commodity code, heading, or subheading. Navigates the tariff hierarchy for a 4-10 digit goods nomenclature code and helps find valid 10-digit commodity codes before calling lookup_commodity. For natural-language product descriptions, start with classification_search. Codes shorter than 10 digits are automatically zero-padded."

  input_schema(
    properties: {
      code: {
        type: "string",
        description: "4 to 10-digit goods nomenclature code, e.g. '0101' or '0101210000'.",
        pattern: "^\\d{4,10}$"
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
