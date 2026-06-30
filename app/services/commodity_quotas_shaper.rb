# frozen_string_literal: true

# Extracts quota order numbers from a commodity response so the tool
# can fetch live quota balances in a second step. Country filtering is
# done server-side (filter.geographical_area_id) by the caller, not here.
class CommodityQuotasShaper < ApplicationShaper
  def self.call(api_response, country_code: nil)
    new(api_response, country_code: country_code).call
  end

  def initialize(api_response, country_code: nil)
    @data         = api_response["data"]
    @included     = build_index(api_response["included"] || [])
    @country_code = country_code
  end

  def call
    refs   = @data.dig("relationships", "import_measures", "data") || []
    orders = extract_order_numbers(refs)

    {
      commodity_code: @data.dig("attributes", "goods_nomenclature_item_id"),
      order_numbers: orders
    }
  end

  private

  def extract_order_numbers(refs)
    refs.filter_map do |ref|
      measure = lookup(ref["type"], ref["id"])
      next unless measure

      on_ref = measure.dig("relationships", "order_number", "data")
      next unless on_ref

      on = lookup(on_ref["type"], on_ref["id"])
      on&.dig("attributes", "number")
    end.uniq
  end
end
