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

    import = @direction == "export" ? [] : shape_measures(rels.dig("import_measures", "data") || [])
    export = @direction == "import" ? [] : shape_measures(rels.dig("export_measures", "data") || [])

    {
      commodity_code: @data.dig("attributes", "goods_nomenclature_item_id"),
      country_filter: @country_code,
      direction: @direction,
      import_measures: import,
      export_measures: export
    }.compact
  end
end
