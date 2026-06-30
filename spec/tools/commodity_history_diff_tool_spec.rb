# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityHistoryDiffTool do
  let(:base_url) { "https://example.com" }
  let(:commodity_body) { File.read("spec/fixtures/api/commodity.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "makes two commodity requests (one per date)" do
    stub_from = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
                  .with(query: hash_including("as_of" => "2024-01-01"))
                  .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })
    stub_to   = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
                  .with(query: hash_including("as_of" => "2025-01-01"))
                  .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000", from_date: "2024-01-01", to_date: "2025-01-01")

    expect(stub_from).to have_been_requested
    expect(stub_to).to have_been_requested
  end

  it "returns a response with changes key" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", from_date: "2024-01-01", to_date: "2025-01-01")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("changes")
  end

  it "returns an error for a missing from_date" do
    result = described_class.call(commodity_code: "0101210000", from_date: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("from_date")
  end

  it "returns an error when from_date is after to_date" do
    result = described_class.call(commodity_code: "0101210000", from_date: "2025-01-01", to_date: "2024-01-01")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("from_date")
  end

  it "returns an error for an invalid commodity_code" do
    result = described_class.call(commodity_code: "short", from_date: "2024-01-01")
    expect(result.error?).to be true
  end
end
