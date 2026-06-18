# frozen_string_literal: true

class SearchQuotasTool < ApplicationTool
  tool_name "search_quotas"
  description "Search quota definitions. Use this to check whether a commodity qualifies for quota relief and what the current quota balance is."

  input_schema(
    properties: {
      order_number: {
        type: "string",
        description: "Filter by quota order number (exactly 6 digits, e.g. '094011').",
        pattern: "\\A\\d{6}\\z"
      },
      year: {
        type: "integer",
        description: "Filter by validity year."
      },
      month: {
        type: "integer",
        description: "Filter by validity month (1–12).",
        minimum: 1,
        maximum: 12
      },
      day: {
        type: "integer",
        description: "Filter by validity day (1–31).",
        minimum: 1,
        maximum: 31
      },
      page: {
        type: "integer",
        description: "Page number (default: 1).",
        minimum: 1
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    }
  )

  def self.call(order_number: nil, year: nil, month: nil, day: nil, page: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date)
    return error if error

    params = {
      "include" => "order_number,order_number.geographical_areas",
      "fields[definition]" => "description,status,balance,initial_volume,measurement_unit,validity_start_date,validity_end_date",
      "fields[order_number]" => "number",
      "fields[geographical_area]" => "id,description,geographical_area_id"
    }
    params["order_number"] = order_number if order_number
    params["year"] = year if year
    params["month"] = month if month
    params["day"] = day if day
    params["page"] = page if page

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/quotas/search", params: params, as_of: validity_date)
      text_response(SearchQuotasShaper.call(raw))
    end
  end
end
