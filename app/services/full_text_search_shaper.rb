# frozen_string_literal: true

# Normalises the backend /api/search (Api::V2::SearchController#search) response into
# a flat list of commodity results. See FullTextSearchTool for the endpoint-verification
# notes — there is no separate legal-notes search endpoint in the backend, so this shaper
# only ever emits { kind: "commodity", code: "...", description: "..." } results, sourced
# from the "goods_nomenclature_match" branch of a fuzzy_search response. The "reference_match"
# branch (search references / synonyms) is not surfaced as it does not represent commodity
# description text.
class FullTextSearchShaper < ApplicationShaper
  class UnsupportedSearchType < StandardError; end

  GOODS_NOMENCLATURE_LEVELS = %w[chapters headings commodities].freeze

  def self.call(api_response, query:, search_type: "all")
    new(api_response, query: query, search_type: search_type).call
  end

  def initialize(api_response, query:, search_type: "all")
    raise UnsupportedSearchType, "notes search is not available: the backend has no legal-notes search endpoint" if search_type == "notes"

    @api_response = api_response
    @query        = query
    @search_type  = search_type
  end

  def call
    {
      query: @query,
      search_type: @search_type,
      results: shape_results
    }
  end

  private

  def shape_results
    match = @api_response.dig("data", "attributes", "goods_nomenclature_match")
    return [] unless match

    GOODS_NOMENCLATURE_LEVELS.flat_map { |level| shape_level(match[level]) }
  end

  def shape_level(hits)
    return [] if hits.blank?

    hits.filter_map do |hit|
      source = hit["_source"]
      next unless source

      {
        kind: "commodity",
        code: source["goods_nomenclature_item_id"],
        description: source["description"]
      }
    end
  end
end
