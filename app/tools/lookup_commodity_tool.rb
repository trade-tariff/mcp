# frozen_string_literal: true

class LookupCommodityTool < ApplicationTool
  tool_name "lookup_commodity"
  description "Look up a 10-digit commodity code. Returns the full commodity record including hierarchy (section, chapter, heading), footnotes, and all tariff measures. Use measures_only: true with an optional country_code and direction to get just the applicable duty rates without the hierarchy — equivalent to the former commodity_measures tool. Do not guess or construct commodity codes; use classification_search or navigate_hierarchy first."

  FULL_INCLUDE = [
    "section,chapter,heading,footnotes",
    "import_measures,import_measures.measure_type,import_measures.duty_expression",
    "import_measures.geographical_area,import_measures.measure_conditions,import_measures.order_number",
    "export_measures,export_measures.measure_type,export_measures.duty_expression",
    "export_measures.geographical_area,export_measures.measure_conditions"
  ].join(",").freeze

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
      measures_only: {
        type: "boolean",
        description: "When true, returns only tariff measures (no hierarchy or footnotes). Combine with country_code and direction for filtered duty lookups."
      },
      country_code: {
        type: "string",
        description: "ISO alpha-2 country code (e.g. 'CN', 'US'). Filters measures to those applicable to that origin plus ERGA OMNES."
      },
      direction: {
        type: "string",
        description: "Which measures to return: 'import' (default), 'export', or 'both'. Only applies when measures_only is true.",
        enum: %w[import export both]
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "commodity_code" ]
  )

  def self.call(commodity_code:, measures_only: false, country_code: nil, direction: "both", service: nil, validity_date: nil, server_context: nil)
    error = validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") ||
            validate_direction(direction) ||
            validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      if measures_only
        params = { "include" => MEASURES_INCLUDE }
        params["filter.geographical_area_id"] = country_code if country_code
        raw = client_for(service: resolved).get("/#{resolved}/api/v2/commodities/#{commodity_code}", params: params, as_of: validity_date)
        text_response(CommodityMeasuresShaper.call(raw, country_code: country_code, direction: direction))
      else
        params = build_full_params
        raw = client_for(service: resolved).get("/#{resolved}/api/v2/commodities/#{commodity_code}", params: params, as_of: validity_date)
        text_response(CommodityShaper.call(raw))
      end
    end
  end

  def self.build_full_params
    {
      "include" => FULL_INCLUDE,
      "fields[commodity]" => "goods_nomenclature_item_id,description_plain,declarable,basic_duty_rate,validity_start_date,validity_end_date,import_measures,export_measures,section,chapter,heading,footnotes",
      "fields[measure]" => "effective_start_date,effective_end_date,excise,vat,reduction_indicator,measure_type,duty_expression,geographical_area,measure_conditions,order_number",
      "fields[measure_type]" => "description",
      "fields[duty_expression]" => "base",
      "fields[geographical_area]" => "id,description,geographical_area_id",
      "fields[measure_condition]" => "condition,document_code,certificate_description,requirement,action",
      "fields[order_number]" => "number",
      "fields[section]" => "title",
      "fields[chapter]" => "formatted_description",
      "fields[heading]" => "description_plain",
      "fields[footnote]" => "code,description"
    }
  end
  private_class_method :build_full_params

  def self.validate_direction(direction)
    return nil if %w[import export both].include?(direction)

    MCP::Tool::Response.new(
      [ { type: "text", text: "Invalid direction: '#{direction}'. Must be 'import', 'export', or 'both'." } ],
      error: true
    )
  end
  private_class_method :validate_direction
end
