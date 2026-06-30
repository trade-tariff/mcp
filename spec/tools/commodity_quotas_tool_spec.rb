# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityQuotasTool do
  let(:base_url) { "https://example.com" }

  def commodity_body_with_quota(order_number)
    {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => {
          "import_measures" => {
            "data" => [ { "id" => "m1", "type" => "measure" } ]
          }
        }
      },
      "included" => [
        {
          "id" => "m1", "type" => "measure",
          "attributes" => {},
          "relationships" => {
            "order_number"      => { "data" => { "id" => "on1", "type" => "order_number" } },
            "geographical_area" => { "data" => { "id" => "1011", "type" => "geographical_area" } }
          }
        },
        { "id" => "on1", "type" => "order_number", "attributes" => { "number" => order_number } },
        { "id" => "1011", "type" => "geographical_area",
          "attributes" => { "geographical_area_id" => "1011", "description" => "ERGA OMNES" } }
      ]
    }.to_json
  end

  let(:quota_body) { File.read("spec/fixtures/api/quotas.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "makes a commodity request then a quota search request per order number" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body_with_quota("094011"),
                 headers: { "Content-Type" => "application/json" })
    quota_stub = stub_request(:get, /uk\/api\/v2\/quotas\/search/)
                   .with(query: hash_including("order_number" => "094011"))
                   .to_return(status: 200, body: quota_body,
                              headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000")

    expect(quota_stub).to have_been_requested
  end

  it "returns a response with commodity_code and quotas" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body_with_quota("094011"),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, /uk\/api\/v2\/quotas\/search/)
      .to_return(status: 200, body: quota_body,
                 headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("commodity_code", "quotas")
  end

  it "returns empty quotas and a message when no quota measures found" do
    no_quota_body = {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => { "import_measures" => { "data" => [] } }
      },
      "included" => []
    }.to_json
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: no_quota_body,
                 headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed["quotas"]).to eq([])
  end

  it "passes filter.geographical_area_id to the backend when country_code is given" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body_with_quota("094011"),
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, /uk\/api\/v2\/quotas\/search/)
      .to_return(status: 200, body: quota_body, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000", country_code: "CN")

    expect(WebMock).to have_requested(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .with(query: hash_including("filter.geographical_area_id" => "CN"))
  end

  it "returns an error for an invalid commodity_code" do
    result = described_class.call(commodity_code: "short")
    expect(result.error?).to be true
  end
end
