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

  def measure(id, type_id, duty_id, geo_id, vat: false, excise: false)
    {
      "id" => id, "type" => "measure",
      "attributes" => { "vat" => vat, "excise" => excise, "reduction_indicator" => nil,
                        "effective_start_date" => nil, "effective_end_date" => nil },
      "relationships" => {
        "measure_type"     => { "data" => { "id" => type_id, "type" => "measure_type" } },
        "duty_expression"  => { "data" => { "id" => duty_id, "type" => "duty_expression" } },
        "geographical_area"=> { "data" => { "id" => geo_id,  "type" => "geographical_area" } },
        "order_number"     => { "data" => nil },
        "measure_conditions" => { "data" => [] }
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
      import_refs: [{ "id" => "m1", "type" => "measure" }, { "id" => "m2", "type" => "measure" }],
      included: [geo_erga, geo_cn, mtype, duty, m_erga, m_cn]
    )
  end

  it "returns all import measures when no country_code given" do
    result = described_class.call(response, country_code: nil, direction: "import")
    expect(result[:import_measures].length).to eq(2)
    expect(result[:export_measures]).to eq([])
  end

  it "filters to country-specific + ERGA OMNES when country_code given" do
    result = described_class.call(response, country_code: "CN", direction: "import")
    expect(result[:import_measures].length).to eq(2)
    expect(result[:import_measures].map { |m| m[:geographical_area] }).to include("ERGA OMNES (1011)", "China (CN)")
  end

  it "returns only ERGA OMNES when filtering to a country with no country-specific measure" do
    # response only has ERGA OMNES and China measures, no Germany measure
    result = described_class.call(response, country_code: "DE", direction: "import")
    # Should return ERGA OMNES as the fallback
    expect(result[:import_measures].length).to eq(1)
    expect(result[:import_measures].first[:geographical_area]).to eq("ERGA OMNES (1011)")
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

  it "returns ERGA OMNES measure when no country-specific measure exists" do
    response_with_only_erga = api_response(
      import_refs: [{ "id" => "m1", "type" => "measure" }],
      included: [geo_erga, mtype, duty, m_erga]
    )
    result = described_class.call(response_with_only_erga, country_code: "JP", direction: "import")
    expect(result[:import_measures].length).to eq(1)
    expect(result[:import_measures].first[:geographical_area]).to eq("ERGA OMNES (1011)")
  end
end
