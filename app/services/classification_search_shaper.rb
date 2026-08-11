# frozen_string_literal: true

class ClassificationSearchShaper
  def self.call(api_response)
    new(api_response).call
  end

  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"] || {}
  end

  def call
    {
      retrieval_method: @meta["retrieval_method"],
      result_count: @meta["result_count"],
      results: @data.map { |item| shape_result(item) }
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
end
