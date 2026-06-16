# frozen_string_literal: true

require "rails_helper"

RSpec.describe LookupCommodityTool do
  let(:uk_base_url) { "https://uk.example.com" }
  let(:xi_base_url) { "https://xi.example.com" }
  let(:commodity_response) { File.read("spec/fixtures/api/commodity.json") }

  before do
    ENV["TARIFF_UK_API_URL"] = uk_base_url
    ENV["TARIFF_XI_API_URL"] = xi_base_url
  end

  after do
    ENV.delete("TARIFF_UK_API_URL")
    ENV.delete("TARIFF_XI_API_URL")
  end

  it "returns commodity details for UK by default" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/commodities/0101210000")
      .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "calls the XI endpoint when service is xi" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/commodities/0101210000")
      .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: "xi")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "raises StandardError when commodity is not found" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/commodities/9999999999")
      .to_return(status: 404, body: "{}")

    expect { described_class.call(commodity_code: "9999999999", service: nil) }.to raise_error(StandardError, /Not found/)
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
