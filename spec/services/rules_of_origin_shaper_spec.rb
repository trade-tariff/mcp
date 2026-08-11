# frozen_string_literal: true

require "rails_helper"

RSpec.describe RulesOfOriginShaper do
  def api_response(schemes: [], included: [])
    { "data" => schemes, "included" => included }
  end

  def scheme(code: "uk-turkey", title: "UK-Turkey Trade Agreement", unilateral: false, rules_refs: [], rule_sets_refs: [])
    {
      "id" => code,
      "type" => "rules_of_origin_scheme",
      "attributes" => {
        "scheme_code" => code,
        "title" => title,
        "unilateral" => unilateral
      },
      "relationships" => {
        "rules"     => { "data" => rules_refs },
        "rule_sets" => { "data" => rule_sets_refs },
        "proofs"    => { "data" => [] },
        "articles"  => { "data" => [] },
        "links"     => { "data" => [] }
      }
    }
  end

  def rule_resource(id: "1", heading: "0101", description: "Wholly obtained", rule: "WO", alternate_rule: nil)
    {
      "id" => id,
      "type" => "rules_of_origin_rule",
      "attributes" => {
        "id_rule" => id,
        "heading" => heading,
        "description" => description,
        "rule" => rule,
        "alternate_rule" => alternate_rule
      }.compact
    }
  end

  it "returns an empty array when data is absent" do
    expect(described_class.call({})).to eq([])
  end

  it "extracts scheme_code, title, and unilateral from each scheme" do
    output = described_class.call(api_response(schemes: [ scheme ]))
    expect(output.length).to eq(1)
    expect(output.first[:scheme_code]).to eq("uk-turkey")
    expect(output.first[:title]).to eq("UK-Turkey Trade Agreement")
    expect(output.first[:unilateral]).to be false
  end

  it "omits rules key when there are no rules" do
    output = described_class.call(api_response(schemes: [ scheme ]))
    expect(output.first).not_to have_key(:rules)
  end

  it "includes rules content when rules are sideloaded" do
    rule_ref = { "type" => "rules_of_origin_rule", "id" => "1" }
    included = [ rule_resource ]
    s = scheme(rules_refs: [ rule_ref ])

    output = described_class.call(api_response(schemes: [ s ], included: included))

    rules = output.first[:rules]
    expect(rules).not_to be_nil
    expect(rules.length).to eq(1)
    expect(rules.first[:heading]).to eq("0101")
    expect(rules.first[:rule]).to eq("WO")
  end

  it "omits alternate_rule from a rule when nil" do
    rule_ref = { "type" => "rules_of_origin_rule", "id" => "1" }
    included = [ rule_resource(alternate_rule: nil) ]
    s = scheme(rules_refs: [ rule_ref ])

    output = described_class.call(api_response(schemes: [ s ], included: included))

    expect(output.first[:rules].first).not_to have_key(:alternate_rule)
  end
end
