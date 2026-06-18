# frozen_string_literal: true

# Collapses the JSONAPI commodity response (~570KB) into a compact structure
# (~5-10KB) suitable for LLM consumption. The full response uses JSONAPI
# sideloading: all related objects (measures, duty expressions, geographical
# areas, etc.) live in a flat `included` array and are referenced by id/type
# from the main `data` object. This class resolves those references and keeps
# only the fields an LLM needs.
class CommodityShaper
  def self.call(api_response)
    new(api_response).call
  end

  def initialize(api_response)
    @data = api_response["data"]
    @included = build_index(api_response["included"] || [])
  end

  def call
    attrs = @data["attributes"]
    rels  = @data["relationships"]

    {
      commodity_code: attrs["goods_nomenclature_item_id"],
      description: attrs["description_plain"],
      declarable: attrs["declarable"],
      validity_start_date: attrs["validity_start_date"]&.then { |d| d[0, 10] },
      validity_end_date: attrs["validity_end_date"]&.then { |d| d[0, 10] },
      basic_duty_rate: attrs["basic_duty_rate"],
      section: resolve_one(rels, "section")&.dig("attributes", "title"),
      chapter: resolve_one(rels, "chapter")&.then { |c| c.dig("attributes", "description_plain") || c.dig("attributes", "formatted_description") },
      heading: resolve_one(rels, "heading")&.dig("attributes", "description_plain"),
      import_measures: shape_measures(rels.dig("import_measures", "data")),
      export_measures: shape_measures(rels.dig("export_measures", "data")),
      footnotes: shape_footnotes(rels.dig("footnotes", "data"))
    }
  end

  private

  def build_index(included)
    included.each_with_object({}) { |item, h| h[[ item["type"], item["id"] ]] = item }
  end

  def lookup(type, id)
    @included[[ type, id ]]
  end

  def resolve_one(rels, name)
    return nil unless rels

    ref = rels.dig(name, "data")
    return nil unless ref

    lookup(ref["type"], ref["id"])
  end

  def shape_measures(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      measure = lookup(ref["type"], ref["id"])
      next unless measure

      mattrs = measure["attributes"]
      mrels  = measure["relationships"]

      measure_type  = resolve_typed(mrels, "measure_type")
      duty_expr     = resolve_typed(mrels, "duty_expression")
      geo_area      = resolve_typed(mrels, "geographical_area")
      order_number  = resolve_typed(mrels, "order_number")
      conditions    = shape_conditions(mrels.dig("measure_conditions", "data"))

      {
        type: measure_type&.dig("attributes", "description"),
        duty: duty_expr&.dig("attributes", "base"),
        geographical_area: format_geo(geo_area),
        excise: mattrs["excise"] || nil,
        vat: mattrs["vat"] || nil,
        reduction_indicator: mattrs["reduction_indicator"],
        quota_order_number: order_number&.dig("attributes", "number"),
        effective_start_date: mattrs["effective_start_date"]&.then { |d| d[0, 10] },
        effective_end_date: mattrs["effective_end_date"]&.then { |d| d[0, 10] },
        conditions: conditions.empty? ? nil : conditions
      }.compact
    end
  end

  def shape_conditions(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      cond = lookup(ref["type"], ref["id"])
      next unless cond

      cattrs = cond["attributes"]
      {
        condition: cattrs["condition"],
        document_code: cattrs["document_code"].then { |v| v.nil? || v.empty? ? nil : v },
        certificate_description: cattrs["certificate_description"].then { |v| v.nil? || v.empty? ? nil : v },
        requirement: cattrs["requirement"].then { |v| v.nil? || v.empty? ? nil : v },
        action: cattrs["action"]
      }.compact
    end
  end

  def shape_footnotes(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      fn = lookup(ref["type"], ref["id"])
      next unless fn

      fattrs = fn["attributes"]
      { code: fattrs["code"], description: fattrs["description"] }
    end
  end

  def resolve_typed(rels, name)
    ref = rels&.dig(name, "data")
    return nil unless ref

    lookup(ref["type"], ref["id"])
  end

  def format_geo(geo)
    return nil unless geo

    attrs = geo["attributes"]
    id    = attrs["geographical_area_id"] || attrs["id"]
    desc  = attrs["description"]
    desc == id ? id : "#{desc} (#{id})"
  end
end
