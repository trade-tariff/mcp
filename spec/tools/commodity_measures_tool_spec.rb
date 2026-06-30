# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityMeasuresTool do
  let(:base_url) { "https://example.com" }
  let(:commodity_body) { File.read("spec/fixtures/api/commodity.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the UK commodity endpoint with measures-only includes" do
    stub = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000.*import_measures/)
             .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000")

    expect(stub).to have_been_requested
  end

  it "returns a response with import_measures and export_measures keys" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("import_measures", "export_measures")
  end

  it "calls XI endpoint when service is xi" do
    stub_request(:get, /xi\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: "xi")
    expect(result).to be_a(MCP::Tool::Response)
  end

  it "returns an error for invalid commodity_code" do
    result = described_class.call(commodity_code: "abc")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid commodity_code")
  end

  it "returns an error response when commodity is not found" do
    stub_request(:get, /uk\/api\/v2\/commodities\/9999999999/)
      .to_return(status: 404, body: "{}")

    result = described_class.call(commodity_code: "9999999999")
    expect(result.error?).to be true
  end

  it "returns an error for invalid direction" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", direction: "sideways")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("direction")
  end
end
