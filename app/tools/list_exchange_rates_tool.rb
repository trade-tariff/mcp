# frozen_string_literal: true

class ListExchangeRatesTool < ApplicationTool
  tool_name "list_exchange_rates"
  description "List GBP monetary exchange rates used in duty calculations, ordered by validity date (last 5 years)."

  input_schema(
    properties: {
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    }
  )

  def self.call(service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/monetary_exchange_rates", as_of: validity_date)) }
  end
end
