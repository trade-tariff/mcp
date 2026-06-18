# frozen_string_literal: true

# Reduces the commodity search response (~367KB) to a compact list of hits.
# The raw response is a single JSONAPI object whose attributes contain two
# nested match buckets (goods_nomenclature_match and reference_match), each
# holding ElasticSearch _source documents for chapters/headings/commodities.
# An LLM only needs the code, description, score, and declarability.
class SearchCommoditiesShaper
  def self.call(api_response)
    attrs = api_response.dig("data", "attributes") || {}

    {
      goods_nomenclature_matches: shape_nomenclature_match(attrs["goods_nomenclature_match"]),
      reference_matches: shape_reference_match(attrs["reference_match"])
    }
  end

  def self.shape_nomenclature_match(match)
    return {} unless match

    match.transform_values do |hits|
      hits.map do |hit|
        src = hit["_source"]
        {
          code: src["goods_nomenclature_item_id"],
          description: src["description"],
          score: hit["_score"]&.round(2),
          declarable: src["declarable"]
        }.compact
      end
    end
  end

  def self.shape_reference_match(match)
    return {} unless match

    match.transform_values do |hits|
      hits.map do |hit|
        src = hit["_source"]
        ref = src["reference"]
        {
          title: src["title"],
          score: hit["_score"]&.round(2),
          code: ref.is_a?(Hash) ? ref["goods_nomenclature_item_id"] : nil
        }.compact
      end
    end
  end
end
