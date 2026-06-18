# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchQuotasTool do
  let(:base_url) { "https://example.com" }
  let(:response_body) { File.read("spec/fixtures/api/quotas.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the UK quotas search endpoint with no filters by default" do
    stub_request(:get, /uk\/api\/v2\/quotas\/search/)
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("quotas")
  end

  it "passes order_number as a query param when supplied" do
    stub = stub_request(:get, /uk\/api\/v2\/quotas\/search/)
             .with(query: hash_including("order_number" => "094011"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(order_number: "094011")

    expect(stub).to have_been_requested
  end

  it "passes year, month and day as query params when supplied" do
    stub = stub_request(:get, /uk\/api\/v2\/quotas\/search/)
             .with(query: hash_including("year" => "2026", "month" => "6", "day" => "1"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(year: 2026, month: 6, day: 1)

    expect(stub).to have_been_requested
  end

  it "calls the XI endpoint when service is ni" do
    stub_request(:get, /xi\/api\/v2\/quotas\/search/)
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: "ni")

    expect(JSON.parse(result.content.first[:text])).to include("quotas")
  end

  it "returns an error for an invalid validity_date" do
    result = described_class.call(validity_date: "2025/06/01")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid validity_date")
  end

  it "raises StandardError when the backend returns a 5xx status" do
    stub_request(:get, /uk\/api\/v2\/quotas\/search/)
      .to_return(status: 500, body: "{}")

    expect { described_class.call(service: nil) }.to raise_error(StandardError, /API error 500/)
  end
end
