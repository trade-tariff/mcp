# frozen_string_literal: true

class QuotaPortfolioTool < ApplicationTool
  tool_name "quota_portfolio"
  description "Return a paginated portfolio of all quota definitions with utilization figures: volume used, current balance, and utilization percentage. Use this to scan across the whole quota schedule without knowing individual order numbers in advance. Filter by measurement unit or quota type to narrow results."

  input_schema(
    properties: {
      measurement_unit_code: {
        type: "string",
        description: "Filter by measurement unit code (e.g. 'KGM', 'LTR', 'DTN')."
      },
      quota_type: {
        type: "string",
        enum: [ "Licensed", "First Come First Served" ],
        description: "Filter by quota type."
      },
      page: {
        type: "integer",
        description: "Page number (default: 1).",
        minimum: 1
      },
      service: SERVICE_SCHEMA
    }
  )

  def self.call(measurement_unit_code: nil, quota_type: nil, page: nil, service: nil, server_context: nil)
    resolved = ServiceNormaliser.call(service)

    filter = {}
    filter["measurement_unit_code"] = measurement_unit_code if measurement_unit_code
    filter["quota_type"] = quota_type if quota_type

    params = {}
    params["filter"] = filter unless filter.empty?
    params["page"] = page if page

    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/quotas/utilization_summary", params: params)
      text_response(QuotaPortfolioShaper.call(raw))
    end
  end
end
