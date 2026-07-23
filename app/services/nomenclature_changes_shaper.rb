# frozen_string_literal: true

class NomenclatureChangesShaper < ApplicationShaper
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
      change_type: attrs["change_type"],
      commodity_code: attrs["goods_nomenclature_item_id"],
      goods_nomenclature_sid: attrs["goods_nomenclature_sid"],
      productline_suffix: attrs["productline_suffix"],
      end_line: attrs["end_line"],
      change_date: attrs["change_date"]&.then { |d| d[0, 10] }
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
