# frozen_string_literal: true

class MeasureSearchShaper < ApplicationShaper
  TRADE_DIRECTION = { 0 => "import", 1 => "export", 2 => "import and export" }.freeze

  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"]
  end

  def call
    result = { measures: @data.map { |m| shape_measure(m) } }
    result[:meta] = shape_meta(@meta) if @meta
    result
  end

  private

  def shape_measure(record)
    attrs = record["attributes"]
    {
      measure_sid: record["id"]&.to_i,
      commodity_code: attrs["goods_nomenclature_item_id"],
      measure_type_id: attrs["measure_type_id"],
      measure_type_series: attrs["measure_type_series_id"],
      measure_type: attrs["measure_type_description"],
      geographical_area_id: attrs["geographical_area_id"],
      geographical_area: attrs["geographical_area_description"],
      trade_direction: TRADE_DIRECTION[attrs["trade_movement_code"]],
      order_number: attrs["ordernumber"],
      regulation_id: attrs["measure_generating_regulation_id"],
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      has_geographical_exclusions: attrs["has_geographical_exclusions"],
      excluded_geographical_area_ids: attrs["excluded_geographical_area_ids"]&.then { |e| e.empty? ? nil : e },
      reduction_indicator: attrs["reduction_indicator"]
    }.compact
  end

  def shape_meta(meta)
    { as_of: meta["as_of"], pagination: meta["pagination"] }.compact
  end
end
