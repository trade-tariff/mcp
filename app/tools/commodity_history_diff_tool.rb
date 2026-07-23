# frozen_string_literal: true

class CommodityHistoryDiffTool < ApplicationTool
  tool_name "commodity_history_diff"
  description "Show what changed for a specific commodity between two dates: measures added or removed, and duty rate changes. Provide from_date and optionally to_date (defaults to today). Useful for auditing tariff changes or understanding why duty rates differ from a previous period."

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "^\\d{10}$"
      },
      from_date: {
        type: "string",
        description: "Start date for the comparison (YYYY-MM-DD).",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      to_date: {
        type: "string",
        description: "End date for the comparison (YYYY-MM-DD). Defaults to today.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      service: SERVICE_SCHEMA
    },
    required: %w[commodity_code from_date]
  )

  def self.call(commodity_code:, from_date:, to_date: nil, service: nil, server_context: nil)
    to_date ||= Date.today.to_s

    error = validate_required(from_date, "from_date") ||
            validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") ||
            validate_date(from_date) ||
            validate_date(to_date) ||
            validate_date_order(from_date, to_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      params = { "include" => CommodityMeasuresTool::MEASURES_INCLUDE }
      client  = client_for(service: resolved)

      from_raw = client.get("/#{resolved}/api/v2/commodities/#{commodity_code}", params: params, as_of: from_date)
      to_raw   = client.get("/#{resolved}/api/v2/commodities/#{commodity_code}", params: params, as_of: to_date)

      from_shaped = CommodityMeasuresShaper.call(from_raw, direction: "both")
      to_shaped   = CommodityMeasuresShaper.call(to_raw,   direction: "both")

      from_measures = (from_shaped[:import_measures] || []) + (from_shaped[:export_measures] || [])
      to_measures   = (to_shaped[:import_measures]   || []) + (to_shaped[:export_measures]   || [])

      text_response(
        CommodityHistoryDiffShaper.call(
          commodity_code: commodity_code,
          from_date: from_date,
          to_date: to_date,
          from_measures: from_measures,
          to_measures: to_measures
        )
      )
    end
  end

end
