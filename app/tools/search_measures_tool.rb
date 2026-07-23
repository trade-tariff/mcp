# frozen_string_literal: true

class SearchMeasuresTool < ApplicationTool
  tool_name "search_measures"
  description "Search for measures across all commodities using composable filters. Use this when you need to find measures by type, country, trade direction, or other criteria without starting from a known commodity code. Returns paginated measure records. For aggregate counts by series instead of records, use summarise_measures."

  input_schema(
    properties: {
      measure_type_series: {
        type: "array",
        items: { type: "string" },
        description: "Filter by measure type series. A=prohibitions, B=restrictions, C=duties, D=anti-dumping, Q=excise, etc."
      },
      measure_type_ids: {
        type: "array",
        items: { type: "string" },
        description: "Filter by exact measure type codes (e.g. ['103', '105'])."
      },
      geographical_area_id: {
        type: "string",
        description: "Filter by geographical area ID. Use 'erga_omnes' for measures applying to all countries."
      },
      has_no_geographical_exclusions: {
        type: "boolean",
        description: "When true, return only measures with no country exclusions."
      },
      has_no_exemption_conditions: {
        type: "boolean",
        description: "When true, return only measures with no Y-type certificate conditions."
      },
      trade_direction: {
        type: "string",
        enum: %w[import export],
        description: "Filter by trade direction."
      },
      commodity_code_prefix: {
        type: "string",
        description: "Filter by 2–10 digit commodity code prefix.",
        pattern: "^\\d{2,10}$"
      },
      regulation_id: {
        type: "string",
        description: "Filter by generating regulation ID."
      },
      measure_condition_codes: {
        type: "array",
        items: { type: "string" },
        description: "Filter by measure condition codes (e.g. ['B', 'E'])."
      },
      has_ad_valorem: {
        type: "boolean",
        description: "When true, return only measures with percentage-based duty components."
      },
      as_of: {
        type: "string",
        description: "Return measures valid on this date (YYYY-MM-DD). Defaults to today.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      page: {
        type: "integer",
        description: "Page number (default: 1).",
        minimum: 1
      },
      per_page: {
        type: "integer",
        description: "Results per page (default: 25, max: 100).",
        minimum: 1,
        maximum: 100
      },
      service: SERVICE_SCHEMA
    }
  )

  def self.call(
    measure_type_series: nil,
    measure_type_ids: nil,
    geographical_area_id: nil,
    has_no_geographical_exclusions: nil,
    has_no_exemption_conditions: nil,
    trade_direction: nil,
    commodity_code_prefix: nil,
    regulation_id: nil,
    measure_condition_codes: nil,
    has_ad_valorem: nil,
    as_of: nil,
    page: nil,
    per_page: nil,
    service: nil,
    server_context: nil
  )
    error = validate_date(as_of)
    return error if error

    resolved = ServiceNormaliser.call(service)

    filter = {}
    filter["measure_type_series"] = measure_type_series if measure_type_series
    filter["measure_type_ids"] = measure_type_ids if measure_type_ids
    filter["geographical_area_id"] = geographical_area_id if geographical_area_id
    filter["has_no_geographical_exclusions"] = has_no_geographical_exclusions unless has_no_geographical_exclusions.nil?
    filter["has_no_exemption_conditions"] = has_no_exemption_conditions unless has_no_exemption_conditions.nil?
    filter["trade_direction"] = trade_direction if trade_direction
    filter["commodity_code_prefix"] = commodity_code_prefix if commodity_code_prefix
    filter["regulation_id"] = regulation_id if regulation_id
    filter["measure_condition_codes"] = measure_condition_codes if measure_condition_codes
    filter["has_ad_valorem"] = has_ad_valorem unless has_ad_valorem.nil?

    params = {}
    params["filter"] = filter unless filter.empty?
    params["page"] = page if page
    params["per_page"] = per_page if per_page

    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/measures/search", params: params, as_of: as_of)
      text_response(MeasureSearchShaper.call(raw))
    end
  end
end
