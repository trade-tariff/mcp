# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuotaPortfolioTool do
  let(:base_url) { "https://example.com" }
  let(:body) { File.read("spec/fixtures/api/quota_portfolio.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the quota utilization summary endpoint" do
    stub = stub_request(:get, /uk\/api\/v2\/quotas\/utilization_summary/)
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call

    expect(stub).to have_been_requested
  end

  it "returns a response with quotas and meta keys" do
    stub_request(:get, /uk\/api\/v2\/quotas\/utilization_summary/)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = described_class.call
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("quotas", "meta")
    expect(parsed["quotas"].first).to include("order_number", "utilization_percentage")
  end

  it "passes measurement_unit_code filter" do
    stub = stub_request(:get, /uk\/api\/v2\/quotas\/utilization_summary/)
             .with(query: hash_including("filter" => hash_including("measurement_unit_code" => "KGM")))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(measurement_unit_code: "KGM")

    expect(stub).to have_been_requested
  end

  it "passes quota_type filter" do
    stub = stub_request(:get, /uk\/api\/v2\/quotas\/utilization_summary/)
             .with(query: hash_including("filter" => hash_including("quota_type" => "Licensed")))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(quota_type: "Licensed")

    expect(stub).to have_been_requested
  end

  it "passes page param" do
    stub = stub_request(:get, /uk\/api\/v2\/quotas\/utilization_summary/)
             .with(query: hash_including("page" => "2"))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(page: 2)

    expect(stub).to have_been_requested
  end

  it "returns an error for a 404 response" do
    stub_request(:get, /uk\/api\/v2\/quotas\/utilization_summary/)
      .to_return(status: 404)

    result = described_class.call
    expect(result.error?).to be true
  end
end
