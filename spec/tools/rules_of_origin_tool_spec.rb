# frozen_string_literal: true

require "rails_helper"

RSpec.describe RulesOfOriginTool do
  let(:base_url) { "https://example.com" }
  let(:response_body) { File.read("spec/fixtures/api/rules_of_origin.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "calls the UK rules of origin endpoint with a padded 6-digit subheading code by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/rules_of_origin_schemes/040900/TR")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(heading_code: "0409", country_code: "TR", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "calls the XI endpoint when service is ni" do
    stub_request(:get, "#{base_url}/xi/api/v2/rules_of_origin_schemes/010100/TR")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(heading_code: "0101", country_code: "TR", service: "ni")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "passes validity_date as as_of query param" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/rules_of_origin_schemes/040900/TR")
             .with(query: hash_including("as_of" => "2025-01-01"))
             .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(heading_code: "0409", country_code: "TR", validity_date: "2025-01-01")

    expect(stub).to have_been_requested
  end

  it "returns an error for a non-numeric heading_code" do
    result = described_class.call(heading_code: "abcd", country_code: "TR")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid heading_code")
  end

  it "returns an error for a heading_code that is not 4 digits" do
    result = described_class.call(heading_code: "04", country_code: "TR")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid heading_code")
  end

  it "returns an error for a country_code that is not 2 uppercase letters" do
    result = described_class.call(heading_code: "0409", country_code: "turkey")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid country_code")
  end

  it "returns an error for an invalid validity_date" do
    result = described_class.call(heading_code: "0409", country_code: "TR", validity_date: "not-a-date")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid validity_date")
  end

  it "returns an error when the backend returns 404" do
    stub_request(:get, "#{base_url}/uk/api/v2/rules_of_origin_schemes/040900/ZZ")
      .to_return(status: 404, body: "{}")

    result = described_class.call(heading_code: "0409", country_code: "ZZ")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end
end
