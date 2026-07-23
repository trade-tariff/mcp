# frozen_string_literal: true

class MeasureChangesShaper < ApplicationShaper
  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"]
  end

  def call
    result = { changes: @data.map { |r| shape_change(r) } }
    result[:meta] = shape_meta(@meta) if @meta
    result
  end

  private

  def shape_change(record)
    attrs = record["attributes"]
    {
      operation: attrs["operation"],
      measure_sid: attrs["measure_sid"],
      measure_type_id: attrs["measure_type_id"],
      commodity_code: attrs["goods_nomenclature_item_id"],
      geographical_area_id: attrs["geographical_area_id"],
      regulation_id: attrs["measure_generating_regulation_id"],
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      operation_date: attrs["operation_date"]&.then { |d| d[0, 10] }
    }.compact
  end

  def shape_meta(meta)
    {
      from_date: meta["from_date"],
      to_date: meta["to_date"],
      pagination: meta["pagination"]
    }.compact
  end
end
