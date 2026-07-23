# frozen_string_literal: true

class QuotaUtilizationShaper < ApplicationShaper
  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"]
  end

  def call
    {
      order_number: @meta&.dig("quota_order_number_id"),
      from_date: @meta&.dig("from_date"),
      to_date: @meta&.dig("to_date"),
      definitions: @data.map { |r| shape_definition(r) }
    }.compact
  end

  private

  def shape_definition(record)
    attrs = record["attributes"]
    {
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      initial_volume: attrs["initial_volume"],
      current_balance: attrs["current_balance"],
      volume_used: attrs["volume_used"],
      utilization_percentage: attrs["utilization_percentage"],
      status: attrs["status"],
      measurement_unit_code: attrs["measurement_unit_code"],
      quota_type: attrs["quota_type"],
      balance_event_summary: attrs["balance_event_summary"]
    }.compact
  end
end
