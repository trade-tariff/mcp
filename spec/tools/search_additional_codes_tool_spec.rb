# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchAdditionalCodesTool do
  let(:base_url) { "https://example.com" }
  let(:response_body) { File.read("spec/fixtures/api/additional_codes.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the UK additional codes search endpoint with no filters by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/additional_codes/search")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "passes description as a query param when supplied" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/additional_codes/search")
             .with(query: hash_including("description" => "sugar"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(description: "sugar")

    expect(stub).to have_been_requested
  end

  it "passes type as a query param when supplied" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/additional_codes/search")
             .with(query: hash_including("type" => "8"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(type: "8")

    expect(stub).to have_been_requested
  end

  it "passes code as a query param when supplied" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/additional_codes/search")
             .with(query: hash_including("code" => "100"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(code: "100")

    expect(stub).to have_been_requested
  end

  it "passes all filters together" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/additional_codes/search")
             .with(query: hash_including("description" => "sugar", "type" => "8", "code" => "100"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(description: "sugar", type: "8", code: "100")

    expect(stub).to have_been_requested
  end

  it "calls the XI endpoint when service is ni" do
    stub_request(:get, "#{base_url}/xi/api/v2/additional_codes/search")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: "ni")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "returns an error for an invalid validity_date" do
    result = described_class.call(validity_date: "not-a-date")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid validity_date")
  end

  it "raises StandardError when the backend returns a 5xx status" do
    stub_request(:get, "#{base_url}/uk/api/v2/additional_codes/search")
      .to_return(status: 500, body: "{}")

    expect { described_class.call(service: nil) }.to raise_error(StandardError, /API error 500/)
  end
end
