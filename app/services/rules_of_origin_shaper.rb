# frozen_string_literal: true

class RulesOfOriginShaper < ApplicationShaper
  def initialize(api_response)
    @data     = api_response["data"] || []
    @included = build_index(api_response["included"] || [])
  end

  def call
    @data.map { |scheme| shape_scheme(scheme) }
  end

  private

  def shape_scheme(scheme)
    attrs = scheme["attributes"]
    rels  = scheme["relationships"] || {}

    rules     = extract_rules(rels.dig("rules", "data") || [])
    rule_sets = extract_rule_sets(rels.dig("rule_sets", "data") || [])

    {
      scheme_code: attrs["scheme_code"],
      title:       attrs["title"],
      unilateral:  attrs["unilateral"],
      rules:       rules.empty? ? nil : rules,
      rule_sets:   rule_sets.empty? ? nil : rule_sets
    }.compact
  end

  def extract_rules(refs)
    refs.filter_map do |ref|
      rule = lookup(ref["type"], ref["id"])
      next unless rule

      rattrs = rule["attributes"]
      {
        heading:        rattrs["heading"],
        description:    rattrs["description"],
        rule:           rattrs["rule"],
        alternate_rule: rattrs["alternate_rule"]
      }.compact
    end
  end

  def extract_rule_sets(refs)
    refs.filter_map do |ref|
      rule_set = lookup(ref["type"], ref["id"])
      next unless rule_set

      rsattrs   = rule_set["attributes"]
      rule_refs = rule_set.dig("relationships", "rules", "data") || []
      v2_rules  = extract_v2_rules(rule_refs)

      {
        heading:    rsattrs["heading"],
        subdivision: rsattrs["subdivision"],
        rules:      v2_rules.empty? ? nil : v2_rules
      }.compact
    end
  end

  def extract_v2_rules(refs)
    refs.filter_map do |ref|
      rule = lookup(ref["type"], ref["id"])
      next unless rule

      rattrs = rule["attributes"]
      {
        rule:       rattrs["rule"],
        rule_class: rattrs["rule_class"],
        operator:   rattrs["operator"]
      }.compact
    end
  end
end
