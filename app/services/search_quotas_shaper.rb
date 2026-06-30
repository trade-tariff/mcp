# frozen_string_literal: true

# Reduces the quota search response (~86KB, 309 included items) to a compact
# list of quotas with their order number and geographical area coverage.
# The bulk of the included array is quota_order_number_origin_exclusion items
# (typically 140+) which list countries explicitly excluded from quota
# origins — these are dropped as they are rarely needed for a first pass.
class SearchQuotasShaper < ApplicationShaper
  def initialize(api_response)
    @data     = api_response["data"] || []
    @included = build_index(api_response["included"] || [])
    @meta     = api_response["meta"]
  end

  def call
    result = { quotas: @data.map { |q| shape_quota(q) } }
    result[:meta] = shape_meta(@meta) if @meta
    result
  end

  private

  def shape_quota(quota)
    attrs = quota["attributes"]
    rels  = quota["relationships"]

    order_ref   = rels.dig("order_number", "data")
    order       = order_ref ? lookup(order_ref["type"], order_ref["id"]) : nil
    geo_areas   = resolve_geo_areas(order)
    commodities = resolve_commodities(rels.dig("measures", "data") || [])

    {
      order_number: order&.dig("attributes", "number"),
      description: attrs["description"],
      status: attrs["status"],
      balance: attrs["balance"],
      initial_volume: attrs["initial_volume"],
      measurement_unit: [ attrs["measurement_unit"], attrs["measurement_unit_qualifier"] ].compact.join(" ").presence,
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      geographical_areas: geo_areas,
      commodities: commodities.uniq
    }.compact
  end

  def resolve_geo_areas(order)
    return [] unless order

    geo_refs = order.dig("relationships", "geographical_areas", "data") || []
    geo_refs.filter_map do |ref|
      geo = lookup(ref["type"], ref["id"])
      next unless geo

      geo_attrs = geo["attributes"]
      {
        id: geo_attrs["geographical_area_id"] || geo_attrs["id"],
        description: geo_attrs["description"]
      }
    end
  end

  def resolve_commodities(measure_refs)
    measure_refs.filter_map do |ref|
      measure = lookup(ref["type"], ref["id"])
      next unless measure

      comm_ref = measure.dig("relationships", "goods_nomenclature", "data")
      next unless comm_ref

      comm = lookup(comm_ref["type"], comm_ref["id"])
      next unless comm

      comm_attrs = comm["attributes"]
      {
        code: comm_attrs["goods_nomenclature_item_id"],
        description: comm_attrs["description_plain"] || comm_attrs["description"]
      }
    end
  end

  def shape_meta(meta)
    { pagination: meta["pagination"] }.compact
  end
end
