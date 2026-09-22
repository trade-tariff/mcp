# frozen_string_literal: true

class ClassificationSearchShaper
  def self.call(api_response, query: nil, expanded_query: nil)
    new(api_response, query: query, expanded_query: expanded_query).call
  end

  def initialize(api_response, query: nil, expanded_query: nil)
    @data = api_response["data"] || []
    @meta = api_response["meta"] || {}
    @query = query
    @expanded_query = expanded_query
  end

  # Relative match bands, measured against the top-scoring result in *this*
  # response only. The underlying score is a hybrid (semantic + keyword)
  # retrieval score, not a calibrated probability. A band therefore means "how
  # close to the best match found for this query" and never "how likely this is
  # the correct code". Two queries that both return a "high" band have not made
  # the same claim: the band is recomputed from scratch for each query, so the
  # best of a weak candidate set still bands as "high".
  HIGH_MATCH_RATIO = 0.85
  MEDIUM_MATCH_RATIO = 0.5

  RELATIVE_MATCH_NOTE = "band and ratio_to_top_result compare each result to the best result for THIS query only. " \
                        "They are not a probability that the code is correct. They are not comparable between " \
                        "queries, so never rank or compare items of a batch by them. A weak candidate set still " \
                        "produces a 'high' band. Verify every code through navigate_hierarchy, show_heading, and " \
                        "the chapter and section notes before you report it."

  def call
    results = @data.map { |item| shape_result(item) }

    {
      query: @query.presence,
      expanded_query: @expanded_query.presence,
      retrieval_method: @meta["retrieval_method"],
      result_count: @meta["result_count"],
      results: with_relative_match(results),
      relative_match_note: RELATIVE_MATCH_NOTE
    }.compact
  end

  private

  def shape_result(item)
    attrs = item["attributes"]
    {
      code: attrs["goods_nomenclature_item_id"],
      sid: attrs["goods_nomenclature_sid"],
      description: attrs["description"],
      declarable: attrs["declarable"],
      score: attrs["score"]
    }.compact
  end

  def with_relative_match(results)
    top_score = results.filter_map { |r| r[:score] }.max
    return results if top_score.nil? || top_score.zero?

    results.map do |r|
      next r unless r[:score]

      ratio = r[:score] / top_score.to_f
      r.merge(relative_match: { band: match_band(ratio), ratio_to_top_result: ratio.round(3) })
    end
  end

  def match_band(ratio)
    if ratio >= HIGH_MATCH_RATIO
      "high"
    elsif ratio >= MEDIUM_MATCH_RATIO
      "medium"
    else
      "low"
    end
  end
end
