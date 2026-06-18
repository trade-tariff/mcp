# frozen_string_literal: true

require "rails_helper"

RSpec.describe ListGeographicalAreasTool do
  let(:base_url) { "https://example.com" }
  let(:response_body) { File.read("spec/fixtures/api/geographical_areas.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the UK geographical areas endpoint by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/geographical_areas")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to be_an(Array)
  end

  it "calls the XI endpoint when service is xi" do
    stub_request(:get, "#{base_url}/xi/api/v2/geographical_areas")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: "xi")

    expect(JSON.parse(result.content.first[:text])).to be_an(Array)
  end

  it "passes validity_date as as_of query param" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/geographical_areas")
             .with(query: hash_including("as_of" => "2025-06-01"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(validity_date: "2025-06-01")

    expect(stub).to have_been_requested
  end

  it "returns an error for an invalid validity_date" do
    result = described_class.call(validity_date: "31-13-2025")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid validity_date")
  end

  it "raises StandardError when the backend returns a 5xx status" do
    stub_request(:get, "#{base_url}/uk/api/v2/geographical_areas")
      .to_return(status: 500, body: "{}")

    expect { described_class.call(service: nil) }.to raise_error(StandardError, /API error 500/)
  end
end
