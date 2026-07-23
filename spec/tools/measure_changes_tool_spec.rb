# frozen_string_literal: true

require "rails_helper"

RSpec.describe MeasureChangesTool do
  let(:base_url) { "https://example.com" }
  let(:body) { File.read("spec/fixtures/api/measure_changes.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the measures diff endpoint with date params" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/diff/)
             .with(query: hash_including("from_date" => "2025-01-01", "to_date" => "2025-01-31"))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(from_date: "2025-01-01", to_date: "2025-01-31")

    expect(stub).to have_been_requested
  end

  it "returns a response with changes and meta keys" do
    stub_request(:get, /uk\/api\/v2\/measures\/diff/)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(from_date: "2025-01-01")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("changes", "meta")
  end

  it "defaults to_date to today" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/diff/)
             .with(query: hash_including("to_date" => Date.today.to_s))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(from_date: "2025-01-01")

    expect(stub).to have_been_requested
  end

  it "returns an error when from_date is missing" do
    result = described_class.call(from_date: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("from_date")
  end

  it "returns an error when from_date is after to_date" do
    result = described_class.call(from_date: "2025-02-01", to_date: "2025-01-01")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("from_date")
  end

  it "returns an error for a 404 response" do
    stub_request(:get, /uk\/api\/v2\/measures\/diff/)
      .to_return(status: 404)

    result = described_class.call(from_date: "2025-01-01")
    expect(result.error?).to be true
  end
end
