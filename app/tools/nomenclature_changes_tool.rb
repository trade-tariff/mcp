# frozen_string_literal: true

class NomenclatureChangesTool < ApplicationTool
  tool_name "nomenclature_changes"
  description "Return goods nomenclature structural changes (headings or commodity codes added, removed, or modified) within a date range. Use this to find out what commodity codes were created or retired in a given period. Paginated — use page to retrieve further results."

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
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/changes_by_period", params: params)
      text_response(NomenclatureChangesShaper.call(raw))
    end
  end
end
