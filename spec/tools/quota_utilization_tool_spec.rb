# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuotaUtilizationTool do
  let(:base_url) { "https://example.com" }
  let(:body) { File.read("spec/fixtures/api/quota_utilization.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the quota order number utilization endpoint" do
    stub = stub_request(:get, /uk\/api\/v2\/quota_order_numbers\/094011\/utilization/)
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(order_number: "094011")

    expect(stub).to have_been_requested
  end

  it "returns a response with order_number and definitions keys" do
    stub_request(:get, /uk\/api\/v2\/quota_order_numbers\/094011\/utilization/)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(order_number: "094011")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("order_number", "definitions")
    expect(parsed["order_number"]).to eq("094011")
  end

  it "passes date range params when provided" do
    stub = stub_request(:get, /uk\/api\/v2\/quota_order_numbers\/094011\/utilization/)
             .with(query: hash_including("from_date" => "2025-01-01", "to_date" => "2025-06-30"))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(order_number: "094011", from_date: "2025-01-01", to_date: "2025-06-30")

    expect(stub).to have_been_requested
  end

  it "returns an error for an invalid order_number format" do
    result = described_class.call(order_number: "short")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("order_number")
  end

  it "returns an error when from_date is after to_date" do
    result = described_class.call(order_number: "094011", from_date: "2025-06-01", to_date: "2025-01-01")
    expect(result.error?).to be true
  end

  it "returns an error for a 404 response" do
    stub_request(:get, /uk\/api\/v2\/quota_order_numbers\/999999\/utilization/)
      .to_return(status: 404)

    result = described_class.call(order_number: "999999")
    expect(result.error?).to be true
  end
end
