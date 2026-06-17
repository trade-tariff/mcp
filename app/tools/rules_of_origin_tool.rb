# frozen_string_literal: true

class RulesOfOriginTool < ApplicationTool
  tool_name "rules_of_origin"
  description "Return rules of origin schemes applicable to a heading and country combination, including the specific rules, articles, and proof of origin required to claim a preferential rate."

  input_schema(
    properties: {
      heading_code: {
        type: "string",
        description: "4-digit heading code (e.g. '0101').",
        pattern: "\\A\\d{4}\\z"
      },
      country_code: {
        type: "string",
        description: "ISO 2-letter country code (e.g. 'TR' for Turkey).",
        pattern: "\\A[A-Z]{2}\\z"
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "heading_code", "country_code" ]
  )

  def self.call(heading_code:, country_code:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(heading_code, /\A\d{4}\z/, "heading_code") ||
            validate_format(country_code, /\A[A-Z]{2}\z/, "country_code") ||
            validate_date(validity_date)
    return error if error

    subheading_code = "#{heading_code}00"
    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/rules_of_origin_schemes/#{subheading_code}/#{country_code}", as_of: validity_date)) }
  end
end
