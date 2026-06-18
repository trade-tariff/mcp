# frozen_string_literal: true

# Reduces the heading response (~13KB) to a clean summary: heading details,
# hierarchy (section/chapter), footnotes, and a commodity children list with
# codes and descriptions. Drops display-only fields and self-referential data.
class HeadingShaper
  def self.call(api_response)
    new(api_response).call
  end

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
      section: resolve_one(rels, "section")&.dig("attributes", "title"),
      chapter: resolve_chapter(rels),
      footnotes: shape_footnotes(rels.dig("footnotes", "data")),
      commodities: shape_commodities(rels.dig("commodities", "data"))
    }.compact
  end

  private

  def build_index(included)
    included.each_with_object({}) { |item, h| h[[ item["type"], item["id"] ]] = item }
  end

  def lookup(type, id)
    @included[[ type, id ]]
  end

  def resolve_one(rels, name)
    return nil unless rels

    ref = rels.dig(name, "data")
    return nil unless ref

    lookup(ref["type"], ref["id"])
  end

  def resolve_chapter(rels)
    chapter = resolve_one(rels, "chapter")
    return nil unless chapter

    chapter.dig("attributes", "description_plain") ||
      chapter.dig("attributes", "formatted_description")
  end

  def shape_footnotes(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      fn = lookup(ref["type"], ref["id"])
      next unless fn

      { code: fn.dig("attributes", "code"), description: fn.dig("attributes", "description") }
    end
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
