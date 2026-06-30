# frozen_string_literal: true

class DutyVatCalculatorTool < ApplicationTool
  tool_name "duty_vat_calculator"
  description "Return applicable duty rates for a commodity, filtered by origin country. When a customs value is provided, calculates the duty amount and VAT. For ad-valorem (percentage) duties the calculation is automatic. For specific duties (e.g. per kg) provide quantity and unit as well. Rates are returned regardless of whether a value is supplied."

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "\\A\\d{10}\\z"
      },
      country_code: {
        type: "string",
        description: "ISO alpha-2 country code (e.g. 'CN', 'US'). Filters to measures applicable to that origin plus ERGA OMNES."
      },
      customs_value: {
        type: "number",
        description: "Customs value in GBP. When provided, duty amounts are calculated.",
        minimum: 0
      },
      quantity: {
        type: "number",
        description: "Quantity of goods. Required to calculate amounts for specific duties (e.g. per-kg rates).",
        minimum: 0
      },
      unit: {
        type: "string",
        description: "Unit for quantity (e.g. 'kg', 'litre'). Used alongside quantity for specific duty calculations."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: ["commodity_code"]
  )

  def self.call(commodity_code:, country_code: nil, customs_value: nil, quantity: nil, unit: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") ||
            validate_customs_value(customs_value) ||
            validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      raw = client_for(service: resolved).get(
        "/#{resolved}/api/v2/commodities/#{commodity_code}",
        params: { "include" => CommodityMeasuresTool::MEASURES_INCLUDE },
        as_of: validity_date
      )
      text_response(
        DutyVatCalculatorShaper.call(
          raw,
          country_code: country_code,
          customs_value: customs_value,
          quantity: quantity,
          unit: unit
        )
      )
    end
  end

  def self.validate_customs_value(value)
    return nil if value.nil? || value >= 0

    MCP::Tool::Response.new(
      [{ type: "text", text: "Invalid customs_value: must be zero or positive." }],
      error: true
    )
  end
  private_class_method :validate_customs_value
end
