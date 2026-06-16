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
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "commodity_code" ]
  )

  def self.call(commodity_code:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") || validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/commodities/#{commodity_code}", as_of: validity_date)) }
  end
end
