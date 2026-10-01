# frozen_string_literal: true

class ApplicationShaper
  # A measure's effective_start_date is the start date of that measure record, not the
  # date the treatment first applied. DBT changes a measure in one of three ways:
  #
  # - It end-dates the measure and reissues it. It must do this once the measure has
  #   started, so a long-standing treatment can carry a recent start date.
  # - It edits the measure in place, before the measure starts.
  # - It deletes the measure, before the measure starts.
  #
  # The backend keeps only the latest version of each measure. A measure that starts
  # after today can still be edited or deleted, and the earlier version then leaves no trace.
  #
  # Do not call such a measure "provisional". In the tariff that word means a provisional
  # duty or a provisional regulation. Compare the start date with today, not with the
  # validity_date asked for: every measure in a response starts on or before that date.
  MEASURE_DATE_NOTE = "effective_start_date is the start date of this measure record. " \
    "A measure can be end-dated and reissued with new conditions, so the treatment can " \
    "apply from an earlier date than the one shown. Use commodity_history_diff, or " \
    "lookup_commodity with an earlier validity_date, to find when the treatment first applied. " \
    "A measure whose effective_start_date is after today can still be changed or deleted " \
    "before that date, so do not treat its terms as fixed.".freeze

  def self.call(api_response)
    new(api_response).call
  end

  private

  def build_index(included)
    included.each_with_object({}) { |item, h| h[[ item["type"], item["id"] ]] = item }
  end

  def lookup(type, id)
    @included[[ type, id ]]
  end

  def resolve_relationship(rels, name)
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
        action: cattrs["action"],
        # The rate that applies when this condition is met. The action text can be the same
        # for every band of a measure, so this is the only thing that tells them apart.
        duty_expression: cattrs["duty_expression"].then { |v| v.nil? || v.empty? ? nil : v }
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

      measure_type      = resolve_relationship(mrels, "measure_type")
      duty_expr         = resolve_relationship(mrels, "duty_expression")
      geo_area          = resolve_relationship(mrels, "geographical_area")
      order_number      = resolve_relationship(mrels, "order_number")
      additional_code   = resolve_relationship(mrels, "additional_code")
      conditions        = shape_conditions(mrels.dig("measure_conditions", "data"))
      footnotes         = shape_footnotes(mrels.dig("footnotes", "data"))
      type_description  = measure_type&.dig("attributes", "description")
      expression_value  = duty_expr&.dig("attributes", "base")
      supplementary     = type_description&.include?("Supplementary unit")

      {
        type: type_description,
        duty: supplementary ? nil : expression_value,
        unit: supplementary ? expression_value : nil,
        geographical_area: format_geo(geo_area),
        excise: mattrs["excise"] || nil,
        vat: mattrs["vat"] || nil,
        reduction_indicator: mattrs["reduction_indicator"],
        quota_order_number: order_number&.dig("attributes", "number"),
        additional_code: additional_code&.dig("attributes", "code"),
        effective_start_date: mattrs["effective_start_date"]&.then { |d| d[0, 10] },
        effective_end_date: mattrs["effective_end_date"]&.then { |d| d[0, 10] },
        conditions: conditions.empty? ? nil : conditions,
        footnotes: footnotes.empty? ? nil : footnotes
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
