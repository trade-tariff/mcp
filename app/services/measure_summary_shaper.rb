# frozen_string_literal: true

class MeasureSummaryShaper < ApplicationShaper
  def initialize(api_response)
    @meta = api_response["meta"] || {}
  end

  def call
    {
      total_count: @meta["total_count"],
      by_series: @meta["by_series"]
    }.compact
  end
end
