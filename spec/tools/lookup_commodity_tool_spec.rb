# frozen_string_literal: true

require "rails_helper"

RSpec.describe LookupCommodityTool do
  let(:base_url) { "https://example.com" }
  let(:commodity_response) { File.read("spec/fixtures/api/commodity.json") }

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "returns commodity details for UK by default" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("commodity_code")
  end

  it "calls the XI endpoint when service is xi" do
    stub_request(:get, /xi\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: "xi")

    expect(JSON.parse(result.content.first[:text])).to include("commodity_code")
  end

  it "sends sparse field and include params to the API" do
    stub = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
             .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000", service: nil)

    expect(stub).to have_been_requested
    expect(stub.with { |req| req.uri.query }.to_s).to be_truthy
  end

  it "returns an error response when commodity is not found" do
    stub_request(:get, /uk\/api\/v2\/commodities\/9999999999/)
      .to_return(status: 404, body: "{}")

    result = described_class.call(commodity_code: "9999999999", service: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns an error response for a non-numeric commodity_code" do
    result = described_class.call(commodity_code: "../../etc/passwd", service: nil)

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid commodity_code")
  end

  it "raises StandardError for an unrecognised service" do
    expect {
      described_class.call(commodity_code: "0101210000", service: "germany")
    }.to raise_error(StandardError, /Unknown service/)
  end
end
