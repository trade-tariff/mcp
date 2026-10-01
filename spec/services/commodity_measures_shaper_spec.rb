# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityMeasuresShaper do
  def geo(id, desc)
    { "id" => id, "type" => "geographical_area",
      "attributes" => { "geographical_area_id" => id, "description" => desc } }
  end

  def measure_type(id, desc)
    { "id" => id, "type" => "measure_type", "attributes" => { "description" => desc } }
  end

  def duty_expr(id, base)
    { "id" => id, "type" => "duty_expression", "attributes" => { "base" => base } }
  end

  def footnote(code, description)
    { "id" => code, "type" => "footnote", "attributes" => { "code" => code, "description" => description } }
  end

  def additional_code(code, description)
    { "id" => code, "type" => "additional_code",
      "attributes" => { "code" => code, "description" => description } }
  end

  def condition(id, attributes)
    { "id" => id, "type" => "measure_condition", "attributes" => attributes }
  end

  def measure(id, type_id, duty_id, geo_id, vat: false, excise: false, footnote_codes: [],
              additional_code_id: nil, condition_ids: [])
    {
      "id" => id, "type" => "measure",
      "attributes" => { "vat" => vat, "excise" => excise, "reduction_indicator" => nil,
                        "effective_start_date" => nil, "effective_end_date" => nil },
      "relationships" => {
        "measure_type"     => { "data" => { "id" => type_id, "type" => "measure_type" } },
        "duty_expression"  => { "data" => { "id" => duty_id, "type" => "duty_expression" } },
        "geographical_area"=> { "data" => { "id" => geo_id,  "type" => "geographical_area" } },
        "order_number"     => { "data" => nil },
        "additional_code"  => { "data" => additional_code_id ? { "id" => additional_code_id, "type" => "additional_code" } : nil },
        "measure_conditions" => { "data" => condition_ids.map { |c| { "id" => c, "type" => "measure_condition" } } },
        "footnotes" => { "data" => footnote_codes.map { |c| { "id" => c, "type" => "footnote" } } }
      }
    }
  end

  def api_response(import_refs: [], export_refs: [], included: [])
    {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => {
          "import_measures" => { "data" => import_refs },
          "export_measures" => { "data" => export_refs }
        }
      },
      "included" => included
    }
  end

  let(:geo_erga)  { geo("1011", "ERGA OMNES") }
  let(:geo_cn)    { geo("CN", "China") }
  let(:mtype)     { measure_type("103", "Third country duty") }
  let(:duty)      { duty_expr("d1", "12.00 %") }
  let(:m_erga)    { measure("m1", "103", "d1", "1011") }
  let(:m_cn)      { measure("m2", "103", "d1", "CN") }

  let(:response) do
    api_response(
      import_refs: [ { "id" => "m1", "type" => "measure" }, { "id" => "m2", "type" => "measure" } ],
      included: [ geo_erga, geo_cn, mtype, duty, m_erga, m_cn ]
    )
  end

  it "shapes all import measures present in the response (filtering is done server-side)" do
    result = described_class.call(response, country_code: nil, direction: "import")
    expect(result[:import_measures].length).to eq(2)
    expect(result[:export_measures]).to eq([])
  end

  it "returns only export_measures when direction is export" do
    result = described_class.call(response, country_code: nil, direction: "export")
    expect(result[:import_measures]).to be_empty
    expect(result[:export_measures]).to eq([])
  end

  it "includes commodity_code, country_filter, and direction in the result" do
    result = described_class.call(response, country_code: "CN", direction: "both")
    expect(result[:commodity_code]).to eq("0101210000")
    expect(result[:country_filter]).to eq("CN")
    expect(result[:direction]).to eq("both")
  end

  it "shapes whatever measures the backend already filtered to, without re-filtering client-side" do
    response_with_only_erga = api_response(
      import_refs: [ { "id" => "m1", "type" => "measure" } ],
      included: [ geo_erga, mtype, duty, m_erga ]
    )
    result = described_class.call(response_with_only_erga, country_code: "JP", direction: "import")
    expect(result[:import_measures].length).to eq(1)
    expect(result[:import_measures].first[:geographical_area]).to eq("ERGA OMNES (1011)")
  end

  it "shapes the footnotes attached to a measure" do
    m_with_footnote = measure("m3", "103", "d1", "1011", footnote_codes: %w[CD624])
    response_with_footnote = api_response(
      import_refs: [ { "id" => "m3", "type" => "measure" } ],
      included: [ geo_erga, mtype, duty, m_with_footnote,
                  footnote("CD624", "A health entry document is required.") ]
    )

    result = described_class.call(response_with_footnote, direction: "import")

    expect(result[:import_measures].first[:footnotes]).to eq(
      [ { code: "CD624", description: "A health entry document is required." } ]
    )
  end

  it "omits the footnotes key when a measure has no footnotes" do
    result = described_class.call(response, direction: "import")

    expect(result[:import_measures].first).not_to have_key(:footnotes)
  end

  it "returns the additional code on a measure that has one" do
    m = measure("m3", "103", "d1", "1011", additional_code_id: "X411")
    response = api_response(
      import_refs: [ { "id" => "m3", "type" => "measure" } ],
      included: [ geo_erga, mtype, duty, m, additional_code("X411", "Beer, 1.2% to 2.8%") ]
    )

    result = described_class.call(response, country_code: nil, direction: "import")

    expect(result[:import_measures].first[:additional_code]).to eq("X411")
  end

  it "leaves the additional code out when the measure has none" do
    result = described_class.call(response, country_code: nil, direction: "import")

    expect(result[:import_measures].first).not_to have_key(:additional_code)
  end

  # The rate that applies when a condition is met sits in duty_expression, not in the
  # action text. Without it, two excise bands look the same.
  it "returns the duty expression on a measure condition" do
    m = measure("m4", "103", "d1", "1011", condition_ids: [ "c1" ])
    cond = condition("c1", { "condition" => "V", "document_code" => "", "certificate_description" => nil,
                             "requirement" => nil, "action" => "Apply the amount of the action (see components)",
                             "duty_expression" => "9.96 GBP / % vol/hl" })
    response = api_response(
      import_refs: [ { "id" => "m4", "type" => "measure" } ],
      included: [ geo_erga, mtype, duty, m, cond ]
    )

    result = described_class.call(response, country_code: nil, direction: "import")

    expect(result[:import_measures].first[:conditions].first[:duty_expression]).to eq("9.96 GBP / % vol/hl")
  end

  it "leaves a blank duty expression out of the condition" do
    m = measure("m5", "103", "d1", "1011", condition_ids: [ "c2" ])
    cond = condition("c2", { "condition" => "B", "document_code" => "9Y12", "certificate_description" => nil,
                             "requirement" => nil, "action" => "apply", "duty_expression" => "" })
    response = api_response(
      import_refs: [ { "id" => "m5", "type" => "measure" } ],
      included: [ geo_erga, mtype, duty, m, cond ]
    )

    result = described_class.call(response, country_code: nil, direction: "import")

    expect(result[:import_measures].first[:conditions].first).not_to have_key(:duty_expression)
  end
end
