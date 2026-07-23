# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchMeasuresTool do
  let(:base_url) { "https://example.com" }
  let(:body) { File.read("spec/fixtures/api/measure_search.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the measures search endpoint" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/search/)
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call

    expect(stub).to have_been_requested
  end

  it "returns a response with measures key" do
    stub_request(:get, /uk\/api\/v2\/measures\/search/)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    result = described_class.call
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("measures")
  end

  it "passes filter params to the API" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/search/)
             .with(query: hash_including("filter" => hash_including("geographical_area_id" => "CN")))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(geographical_area_id: "CN")

    expect(stub).to have_been_requested
  end

  it "passes trade_direction filter" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/search/)
             .with(query: hash_including("filter" => hash_including("trade_direction" => "import")))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(trade_direction: "import")

    expect(stub).to have_been_requested
  end

  it "passes pagination params" do
    stub = stub_request(:get, /uk\/api\/v2\/measures\/search/)
             .with(query: hash_including("page" => "2", "per_page" => "10"))
             .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    described_class.call(page: 2, per_page: 10)

    expect(stub).to have_been_requested
  end

  it "returns an error for an invalid as_of date" do
    result = described_class.call(as_of: "not-a-date")
    expect(result.error?).to be true
  end

  it "returns an error for a 404 response" do
    stub_request(:get, /uk\/api\/v2\/measures\/search/)
      .to_return(status: 404)

    result = described_class.call
    expect(result.error?).to be true
  end
end
