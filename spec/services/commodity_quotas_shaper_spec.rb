# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityQuotasShaper do
  def measure(id, order_number_id, geo_id)
    {
      "id" => id, "type" => "measure",
      "attributes" => {},
      "relationships" => {
        "order_number"      => order_number_id ? { "data" => { "id" => order_number_id, "type" => "order_number" } } : { "data" => nil },
        "geographical_area" => { "data" => { "id" => geo_id, "type" => "geographical_area" } }
      }
    }
  end

  def order_number(id, number)
    { "id" => id, "type" => "order_number", "attributes" => { "number" => number } }
  end

  def geo(id, desc)
    { "id" => id, "type" => "geographical_area",
      "attributes" => { "geographical_area_id" => id, "description" => desc } }
  end

  def api_response(measure_refs, included)
    {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => { "import_measures" => { "data" => measure_refs } }
      },
      "included" => included
    }
  end

  let(:on_a)    { order_number("on1", "094011") }
  let(:on_b)    { order_number("on2", "094012") }
  let(:geo_cn)  { geo("CN", "China") }
  let(:geo_erga){ geo("1011", "ERGA OMNES") }
  let(:m_cn)    { measure("m1", "on1", "CN") }
  let(:m_erga)  { measure("m2", "on2", "1011") }
  let(:m_none)  { measure("m3", nil, "1011") }

  let(:response) do
    api_response(
      [{ "id" => "m1", "type" => "measure" }, { "id" => "m2", "type" => "measure" }, { "id" => "m3", "type" => "measure" }],
      [on_a, on_b, geo_cn, geo_erga, m_cn, m_erga, m_none]
    )
  end

  it "returns all unique order numbers when no country_code given" do
    result = described_class.call(response, country_code: nil)
    expect(result[:order_numbers]).to contain_exactly("094011", "094012")
  end

  it "filters to matching + ERGA OMNES order numbers when country_code given" do
    result = described_class.call(response, country_code: "CN")
    expect(result[:order_numbers]).to contain_exactly("094011", "094012")
  end

  it "returns empty order_numbers when country has no quota measures and no ERGA OMNES fallback exists" do
    no_erga_response = api_response(
      [{ "id" => "m1", "type" => "measure" }],
      [on_a, geo_cn, m_cn]
    )
    result = described_class.call(no_erga_response, country_code: "DE")
    expect(result[:order_numbers]).to be_empty
  end

  it "skips measures with no order_number" do
    result = described_class.call(response, country_code: nil)
    expect(result[:order_numbers].length).to eq(2)
  end

  it "includes the commodity_code" do
    result = described_class.call(response, country_code: nil)
    expect(result[:commodity_code]).to eq("0101210000")
  end
end
