# frozen_string_literal: true

class DutyVatCalculatorShaper < ApplicationShaper
  ERGA_OMNES_ID = "1011"

  def self.call(api_response, country_code: nil, customs_value: nil, quantity: nil, unit: nil)
    new(api_response,
        country_code: country_code,
        customs_value: customs_value,
        quantity: quantity,
        unit: unit).call
  end

  def initialize(api_response, country_code: nil, customs_value: nil, quantity: nil, unit: nil)
    @data          = api_response["data"]
    @included      = build_index(api_response["included"] || [])
    @country_code  = country_code
    @customs_value = customs_value
    @quantity      = quantity
    @unit          = unit
  end

  def call
    rels         = @data["relationships"]
    measure_refs = rels.dig("import_measures", "data") || []
    measures     = shape_duty_measures(measure_refs)

    total_ad_valorem = select_ad_valorem_total(measures)

    measures = measures.map do |m|
      m = m.reject { |k, _| k == :geo_id }

      next m unless m[:vat]

      vat_rate = percentage_rate(m[:rate])
      next m if @customs_value.nil? || vat_rate.nil?

      m.merge(vat_amount: ((@customs_value + total_ad_valorem) * vat_rate / 100.0).round(2),
              basis: "customs value + duty")
    end

    inputs = {}
    inputs[:customs_value] = @customs_value if @customs_value
    inputs[:currency]      = "GBP" if @customs_value
    inputs[:quantity]      = @quantity if @quantity
    inputs[:unit]          = @unit if @unit

    {
      commodity_code: @data.dig("attributes", "goods_nomenclature_item_id"),
      country: @country_code,
      inputs: inputs,
      applicable_measures: measures
    }.compact
  end

  private

  # Selects the single duty_amount that actually applies for VAT base purposes.
  # Country-specific overrides take priority over the ERGA OMNES fallback; if both
  # are present simultaneously (as happens when filter_by_country admits both), only
  # the country-specific duty_amount is used — it is not summed with ERGA OMNES.
  def select_ad_valorem_total(measures)
    ad_valorem = measures.select { |m| !m[:vat] && m[:duty_amount] }
    return 0.0 if ad_valorem.empty?

    country_specific = ad_valorem.find { |m| @country_code && m[:geo_id] == @country_code }
    return country_specific[:duty_amount] if country_specific

    erga_omnes = ad_valorem.find { |m| m[:geo_id] == ERGA_OMNES_ID }
    (erga_omnes || ad_valorem.first)[:duty_amount]
  end

  def shape_duty_measures(refs)
    refs.filter_map do |ref|
      measure = lookup(ref["type"], ref["id"])
      next unless measure

      mattrs      = measure["attributes"]
      mrels       = measure["relationships"]
      measure_type = resolve_relationship(mrels, "measure_type")
      duty_expr    = resolve_relationship(mrels, "duty_expression")
      geo_area     = resolve_relationship(mrels, "geographical_area")
      duty_str     = duty_expr&.dig("attributes", "base")
      geo_id       = geo_area&.dig("attributes", "geographical_area_id") || geo_area&.dig("attributes", "id")

      result = {
        type: measure_type&.dig("attributes", "description"),
        rate: duty_str,
        geographical_area: format_geo(geo_area),
        vat: mattrs["vat"] || false,
        excise: mattrs["excise"] || false,
        geo_id: geo_id
      }

      rate = percentage_rate(duty_str)

      if mattrs["vat"]
        result
      elsif rate
        if @customs_value
          result.merge(duty_amount: (@customs_value * rate / 100.0).round(2), basis: "customs value")
        else
          result
        end
      else
        note = if @customs_value && duty_str
                 "Cannot calculate amount for specific duty '#{duty_str}' — this tool does not yet resolve specific duty components."
        end
        result.merge(calculation_note: note).compact
      end
    end
  end

  def percentage_rate(rate_str)
    match = rate_str&.match(/(\d+\.?\d*)\s*%/)
    match && match[1].to_f
  end
end
