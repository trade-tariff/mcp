# frozen_string_literal: true

# Reduces the heading response (~13KB) to a clean summary: heading details,
# hierarchy (section/chapter), footnotes, and a commodity children list with
# codes and descriptions. Drops display-only fields and self-referential data.
class HeadingShaper < ApplicationShaper
  def initialize(api_response)
    @data     = api_response["data"]
    @included = build_index(api_response["included"] || [])
  end

  def call
    attrs = @data["attributes"]
    rels  = @data["relationships"]

    {
      heading_code: attrs["goods_nomenclature_item_id"],
      description: attrs["description_plain"],
      declarable: attrs["declarable"],
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      section: resolve_relationship(rels, "section")&.dig("attributes", "title"),
      chapter: resolve_chapter(rels),
      footnotes: shape_footnotes(rels.dig("footnotes", "data")),
      commodities: shape_commodities(rels.dig("commodities", "data"))
    }.compact
  end

  private

  def resolve_chapter(rels)
    chapter = resolve_relationship(rels, "chapter")
    return nil unless chapter

    chapter.dig("attributes", "description_plain") ||
      chapter.dig("attributes", "formatted_description")
  end

  def shape_commodities(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      comm = lookup(ref["type"], ref["id"])
      next unless comm
      next unless comm.dig("attributes", "declarable")

      attrs = comm["attributes"]
      {
        code: attrs["goods_nomenclature_item_id"],
        description: attrs["description_plain"]
      }
    end
  end
end
