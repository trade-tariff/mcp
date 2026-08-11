# frozen_string_literal: true

require "rails_helper"

RSpec.describe RulesOfOriginShaper do
  def api_response(schemes: [])
    { "data" => schemes }
  end

  def scheme(code: "uk-turkey", title: "UK-Turkey Trade Agreement", unilateral: false, extra_attrs: {})
    {
      "id" => code,
      "type" => "rules_of_origin_scheme",
      "attributes" => {
        "scheme_code" => code,
        "title" => title,
        "unilateral" => unilateral
      }.merge(extra_attrs)
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

  it "includes proof_of_origin when present" do
    s = scheme(extra_attrs: { "proof_of_origin" => "EUR.1 movement certificate or origin declaration" })
    output = described_class.call(api_response(schemes: [ s ]))
    expect(output.first[:proof_of_origin]).to include("EUR.1")
  end

  it "omits proof_of_origin when absent" do
    output = described_class.call(api_response(schemes: [ scheme ]))
    expect(output.first).not_to have_key(:proof_of_origin)
  end
end
