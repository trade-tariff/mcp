# frozen_string_literal: true

class ApplicationShaper
  def self.call(api_response)
    new(api_response).call
  end

  private

  def build_index(included)
    included.each_with_object({}) { |item, h| h[[item["type"], item["id"]]] = item }
  end

  def lookup(type, id)
    @included[[type, id]]
  end

  def resolve_one(rels, name)
    return nil unless rels

    ref = rels.dig(name, "data")
    return nil unless ref

    lookup(ref["type"], ref["id"])
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

  def shape_measures(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      measure = lookup(ref["type"], ref["id"])
      next unless measure

      mattrs = measure["attributes"]
      mrels  = measure["relationships"]

      measure_type = resolve_typed(mrels, "measure_type")
      duty_expr    = resolve_typed(mrels, "duty_expression")
      geo_area     = resolve_typed(mrels, "geographical_area")
      order_number = resolve_typed(mrels, "order_number")
      conditions   = shape_conditions(mrels.dig("measure_conditions", "data"))

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

  def shape_footnotes(refs)
    return [] if refs.nil? || refs.empty?

    refs.filter_map do |ref|
      fn = lookup(ref["type"], ref["id"])
      next unless fn

      fattrs = fn["attributes"]
      { code: fattrs["code"], description: fattrs["description"] }
    end
  end
end
