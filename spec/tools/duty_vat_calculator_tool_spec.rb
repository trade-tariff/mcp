# frozen_string_literal: true

require "rails_helper"

RSpec.describe DutyVatCalculatorTool do
  let(:base_url) { "https://example.com" }
  let(:commodity_body) { File.read("spec/fixtures/api/commodity.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the UK commodity endpoint" do
    stub = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
             .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000")

    expect(stub).to have_been_requested
  end

  it "returns a response containing applicable_measures" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("applicable_measures")
  end

  it "passes filter.geographical_area_id to the backend when country_code is given" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000", country_code: "CN")

    expect(WebMock).to have_requested(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .with(query: hash_including("filter.geographical_area_id" => "CN"))
  end

  it "returns an error for an invalid commodity_code" do
    result = described_class.call(commodity_code: "short")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid commodity_code")
  end

  it "returns an error for a negative customs_value" do
    result = described_class.call(commodity_code: "0101210000", customs_value: -100.0)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("customs_value")
  end

  it "returns an error when commodity is not found" do
    stub_request(:get, /uk\/api\/v2\/commodities\/9999999999/)
      .to_return(status: 404, body: "{}")

    result = described_class.call(commodity_code: "9999999999")
    expect(result.error?).to be true
  end
end
