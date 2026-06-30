# frozen_string_literal: true

# Collapses the JSONAPI commodity response (~570KB) into a compact structure
# (~5-10KB) suitable for LLM consumption. The full response uses JSONAPI
# sideloading: all related objects (measures, duty expressions, geographical
# areas, etc.) live in a flat `included` array and are referenced by id/type
# from the main `data` object. This class resolves those references and keeps
# only the fields an LLM needs.
class CommodityShaper < ApplicationShaper
  def initialize(api_response)
    @data     = api_response["data"]
    @included = build_index(api_response["included"] || [])
  end

  def call
    attrs = @data["attributes"]
    rels  = @data["relationships"]

    {
      commodity_code: attrs["goods_nomenclature_item_id"],
      description: attrs["description_plain"],
      declarable: attrs["declarable"],
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      basic_duty_rate: attrs["basic_duty_rate"],
      section: resolve_one(rels, "section")&.dig("attributes", "title"),
      chapter: resolve_one(rels, "chapter")&.then { |c| c.dig("attributes", "description_plain") || c.dig("attributes", "formatted_description") },
      heading: resolve_one(rels, "heading")&.dig("attributes", "description_plain"),
      import_measures: shape_measures(rels.dig("import_measures", "data")),
      export_measures: shape_measures(rels.dig("export_measures", "data")),
      footnotes: shape_footnotes(rels.dig("footnotes", "data"))
    }.compact
  end
end
