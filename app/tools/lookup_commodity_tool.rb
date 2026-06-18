# frozen_string_literal: true

class LookupCommodityTool < ApplicationTool
  tool_name "lookup_commodity"
  description "Look up a commodity by its 10-digit commodity code. Returns description, measures, duties, and other tariff details."

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "\\A\\d{10}\\z"
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "commodity_code" ]
  )

  def self.call(commodity_code:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") || validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      params = {
        "include" => "section,chapter,heading,footnotes," \
                     "import_measures,import_measures.measure_type,import_measures.duty_expression," \
                     "import_measures.geographical_area,import_measures.measure_conditions,import_measures.order_number," \
                     "export_measures,export_measures.measure_type,export_measures.duty_expression," \
                     "export_measures.geographical_area,export_measures.measure_conditions",
        "fields[commodity]" => "goods_nomenclature_item_id,description_plain,declarable,basic_duty_rate,validity_start_date,validity_end_date",
        "fields[measure]" => "effective_start_date,effective_end_date,excise,vat,reduction_indicator",
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
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/commodities/#{commodity_code}", params: params, as_of: validity_date)
      text_response(CommodityShaper.call(raw))
    end
  end
end
