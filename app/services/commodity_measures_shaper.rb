# frozen_string_literal: true

class CommodityMeasuresShaper < ApplicationShaper
  def self.call(api_response, country_code: nil, direction: "both")
    new(api_response, country_code: country_code, direction: direction).call
  end

  def initialize(api_response, country_code: nil, direction: "both")
    @data         = api_response["data"]
    @included     = build_index(api_response["included"] || [])
    @country_code = country_code
    @direction    = direction
  end

  def call
    rels = @data["relationships"]

    import = if @direction == "export"
               []
             else
               shape_measures(filter_by_country(rels.dig("import_measures", "data") || []))
             end

    export = if @direction == "import"
               []
             else
               shape_measures(filter_by_country(rels.dig("export_measures", "data") || []))
             end

    {
      commodity_code: @data.dig("attributes", "goods_nomenclature_item_id"),
      country_filter: @country_code,
      direction: @direction,
      import_measures: import,
      export_measures: export
    }.compact
  end

  private

  def filter_by_country(refs)
    return refs if @country_code.nil?

    refs.select do |ref|
      measure = lookup(ref["type"], ref["id"])
      next false unless measure

      geo_ref = measure.dig("relationships", "geographical_area", "data")
      next false unless geo_ref

      geo    = lookup(geo_ref["type"], geo_ref["id"])
      geo_id = geo&.dig("attributes", "geographical_area_id") || geo&.dig("attributes", "id")
      geo_id == @country_code || geo_id == "1011"
    end
  end
end
