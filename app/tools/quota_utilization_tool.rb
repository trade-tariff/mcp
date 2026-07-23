# frozen_string_literal: true

class QuotaUtilizationTool < ApplicationTool
  tool_name "quota_utilization"
  description "Return utilization details for a specific quota order number: volume used, current balance, utilization percentage, and a timestamped drawdown event summary. Optionally scoped to a date range (defaults to the current year to today)."

  input_schema(
    properties: {
      order_number: {
        type: "string",
        description: "Six-digit quota order number, e.g. '094011'.",
        pattern: "^\\d{6}$"
      },
      from_date: {
        type: "string",
        description: "Start of the utilization period (YYYY-MM-DD). Defaults to the start of the current year.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      to_date: {
        type: "string",
        description: "End of the utilization period (YYYY-MM-DD). Defaults to today.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      service: SERVICE_SCHEMA
    },
    required: %w[order_number]
  )

  def self.call(order_number:, from_date: nil, to_date: nil, service: nil, server_context: nil)
    error = validate_format(order_number, /\A\d{6}\z/, "order_number") ||
            validate_date(from_date) ||
            validate_date(to_date) ||
            validate_date_order(from_date, to_date)
    return error if error

    resolved = ServiceNormaliser.call(service)

    params = {}
    params["from_date"] = from_date if from_date
    params["to_date"] = to_date if to_date

    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/quota_order_numbers/#{order_number}/utilization", params: params)
      text_response(QuotaUtilizationShaper.call(raw))
    end
  end
end
