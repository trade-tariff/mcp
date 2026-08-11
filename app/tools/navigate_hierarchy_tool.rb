# frozen_string_literal: true

class NavigateHierarchyTool < ApplicationTool
  tool_name "navigate_hierarchy"
  description "Navigate the tariff hierarchy to find valid 10-digit commodity codes. Accepts 2-digit chapter codes (e.g. '01'), 4-digit heading codes (e.g. '0101'), or 4-10 digit goods nomenclature codes. Use after classification_search or when you already have a partial code. Codes shorter than 10 digits are zero-padded for goods nomenclature lookup; 2-digit inputs route to the chapter endpoint."

  input_schema(
    properties: {
      code: {
        type: "string",
        description: "2 to 10-digit goods nomenclature code, e.g. '01', '0101', or '0101210000'.",
        pattern: "^\\d{2,10}$"
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "code" ]
  )

  def self.call(code:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(code, /\A\d{2,10}\z/, "code") || validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      raw = if code.length == 2
        client_for(service: resolved).get("/#{resolved}/api/v2/chapters/#{code}", as_of: validity_date)
      else
        padded = code.ljust(10, "0")
        client_for(service: resolved).get("/#{resolved}/api/v2/goods_nomenclatures/#{padded}", as_of: validity_date)
      end
      text_response(NavigateHierarchyShaper.call(raw))
    end
  end
end
