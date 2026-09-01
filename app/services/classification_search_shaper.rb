# frozen_string_literal: true

class ClassificationSearchShaper
  def self.call(api_response)
    new(api_response).call
  end

  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"] || {}
  end

  # Confidence bands, relative to the top-scoring result in *this* response only.
  # The underlying score is a hybrid (semantic + keyword) retrieval score, not a
  # calibrated probability, so confidence here means "how close to the best match
  # found for this query" rather than "how likely this is the correct code."
  HIGH_CONFIDENCE_RATIO = 0.85
  MEDIUM_CONFIDENCE_RATIO = 0.5

  def call
    results = @data.map { |item| shape_result(item) }

    {
      retrieval_method: @meta["retrieval_method"],
      result_count: @meta["result_count"],
      results: with_confidence(results),
      confidence_note: "confidence is relative to the top result in this search only — it is not a calibrated probability. Low or absent confidence means the query did not closely match known descriptions; verify via show_heading or navigate_hierarchy rather than trusting the code."
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

  def with_confidence(results)
    top_score = results.filter_map { |r| r[:score] }.max
    return results if top_score.nil? || top_score.zero?

    results.map do |r|
      next r unless r[:score]

      r.merge(confidence: confidence_band(r[:score] / top_score.to_f))
    end
  end

  def confidence_band(ratio)
    if ratio >= HIGH_CONFIDENCE_RATIO
      "high"
    elsif ratio >= MEDIUM_CONFIDENCE_RATIO
      "medium"
    else
      "low"
    end
  end
end
