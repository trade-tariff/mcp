# frozen_string_literal: true

require "rails_helper"

RSpec.describe SummariseMeasuresTool do
  let(:base_url) { "https://example.com" }
  let(:body) { File.read("spec/fixtures/api/measure_summary.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the measures search endpoint with summary=true" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/search/)
             .with(query: hash_including("summary" => "true"))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call

    expect(stub).to have_been_requested
  end

  it "returns total_count and by_series" do
    stub_request(:get, /uk\/api\/v2\/measures\/search/)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = described_class.call
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("total_count", "by_series")
    expect(parsed["total_count"]).to eq(150)
    expect(parsed["by_series"]).to include("A" => 10, "C" => 100)
  end

  it "passes filter params alongside summary=true" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/search/)
             .with(query: hash_including("summary" => "true", "filter" => hash_including("trade_direction" => "import")))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(trade_direction: "import")

    expect(stub).to have_been_requested
  end

  it "returns an error for an invalid as_of date" do
    result = described_class.call(as_of: "not-a-date")
    expect(result.error?).to be true
  end
end
