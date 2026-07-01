# frozen_string_literal: true

class CommodityMeasuresTool < ApplicationTool
  tool_name "commodity_measures"
  description "Return import and/or export measures for a commodity — duties, licences, restrictions, and quota order numbers — without the hierarchy and footnote data included in lookup_commodity. Useful when you only need to check what measures apply to a specific commodity, optionally filtered by origin or destination country."

  MEASURES_INCLUDE = [
    "import_measures", "import_measures.measure_type", "import_measures.duty_expression",
    "import_measures.geographical_area", "import_measures.measure_conditions", "import_measures.order_number",
    "export_measures", "export_measures.measure_type", "export_measures.duty_expression",
    "export_measures.geographical_area", "export_measures.measure_conditions", "export_measures.order_number"
  ].join(",").freeze

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "^\\d{10}$"
      },
      country_code: {
        type: "string",
        description: "ISO alpha-2 country code or geographical area ID (e.g. 'CN', 'US'). When provided, returns only measures applicable to that country plus ERGA OMNES (all-countries) measures."
      },
      direction: {
        type: "string",
        description: "Which measures to return: 'import' (default), 'export', or 'both'.",
        enum: %w[import export both]
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "commodity_code" ]
  )

  def self.call(commodity_code:, country_code: nil, direction: "both", service: nil, validity_date: nil, server_context: nil)
    error = validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") ||
            validate_direction(direction) ||
            validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      params = { "include" => MEASURES_INCLUDE }
      params["filter.geographical_area_id"] = country_code if country_code

      raw = client_for(service: resolved).get(
        "/#{resolved}/api/v2/commodities/#{commodity_code}",
        params: params,
        as_of: validity_date
      )
      text_response(CommodityMeasuresShaper.call(raw, country_code: country_code, direction: direction))
    end
  end

  def self.validate_direction(direction)
    return nil if %w[import export both].include?(direction)

    MCP::Tool::Response.new(
      [ { type: "text", text: "Invalid direction: '#{direction}'. Must be 'import', 'export', or 'both'." } ],
      error: true
    )
  end
  private_class_method :validate_direction
end
