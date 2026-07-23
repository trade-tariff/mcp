# frozen_string_literal: true

class MeasureChangesTool < ApplicationTool
  tool_name "measure_changes"
  description "Return measure-level changes (created, updated, or deleted) within a date range, across all commodities. Useful for auditing recent tariff activity or finding which measures were affected by a regulation change. Paginated — use page to retrieve further results."

  input_schema(
    properties: {
      from_date: {
        type: "string",
        description: "Start of the date range (YYYY-MM-DD). Required.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      to_date: {
        type: "string",
        description: "End of the date range (YYYY-MM-DD). Defaults to today.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      page: {
        type: "integer",
        description: "Page number (default: 1).",
        minimum: 1
      },
      service: SERVICE_SCHEMA
    },
    required: %w[from_date]
  )

  def self.call(from_date:, to_date: nil, page: nil, service: nil, server_context: nil)
    to_date ||= Date.today.to_s

    error = validate_required(from_date, "from_date") ||
            validate_date(from_date) ||
            validate_date(to_date) ||
            validate_date_order(from_date, to_date)
    return error if error

    resolved = ServiceNormaliser.call(service)

    params = { "from_date" => from_date, "to_date" => to_date }
    params["page"] = page if page

    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/measures/diff", params: params)
      text_response(MeasureChangesShaper.call(raw))
    end
  end
end
