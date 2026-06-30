# frozen_string_literal: true

# Extracts quota order numbers from a commodity response so the tool
# can fetch live quota balances in a second step.
class CommodityQuotasShaper < ApplicationShaper
  ERGA_OMNES_ID = "1011"

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
    refs   = filter_by_country(refs) if @country_code
    orders = extract_order_numbers(refs)

    {
      commodity_code: @data.dig("attributes", "goods_nomenclature_item_id"),
      order_numbers: orders
    }
  end

  private

  def filter_by_country(refs)
    refs.select do |ref|
      measure = lookup(ref["type"], ref["id"])
      next false unless measure

      geo_ref = measure.dig("relationships", "geographical_area", "data")
      next false unless geo_ref

      geo    = lookup(geo_ref["type"], geo_ref["id"])
      geo_id = geo&.dig("attributes", "geographical_area_id") || geo&.dig("attributes", "id")
      geo_id == @country_code || geo_id == ERGA_OMNES_ID
    end
  end

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
