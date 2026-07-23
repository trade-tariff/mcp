# frozen_string_literal: true

class QuotaPortfolioShaper < ApplicationShaper
  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"]
  end

  def call
    result = { quotas: @data.map { |r| shape_quota(r) } }
    result[:meta] = shape_meta(@meta) if @meta
    result
  end

  private

  def shape_quota(record)
    attrs = record["attributes"]
    {
      order_number: attrs["quota_order_number_id"],
      quota_definition_sid: attrs["quota_definition_sid"],
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      initial_volume: attrs["initial_volume"],
      current_balance: attrs["current_balance"],
      volume_used: attrs["volume_used"],
      utilization_percentage: attrs["utilization_percentage"],
      status: attrs["status"],
      measurement_unit_code: attrs["measurement_unit_code"],
      quota_type: attrs["quota_type"]
    }.compact
  end

  def shape_meta(meta)
    { pagination: meta["pagination"] }.compact
  end
end
