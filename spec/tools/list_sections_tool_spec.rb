# frozen_string_literal: true

require "rails_helper"

RSpec.describe ListSectionsTool do
  let(:uk_base_url) { "https://uk.example.com" }
  let(:xi_base_url) { "https://xi.example.com" }
  let(:sections_response) { File.read("spec/fixtures/api/sections.json") }

  before do
    ENV["TARIFF_UK_API_URL"] = uk_base_url
    ENV["TARIFF_XI_API_URL"] = xi_base_url
  end

  after do
    ENV.delete("TARIFF_UK_API_URL")
    ENV.delete("TARIFF_XI_API_URL")
  end

  it "calls the UK sections endpoint by default when service is not given" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/sections")
      .to_return(status: 200, body: sections_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "calls the UK sections endpoint when service is uk" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/sections")
      .to_return(status: 200, body: sections_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: "uk")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "calls the XI sections endpoint when service is ni" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/sections")
      .to_return(status: 200, body: sections_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(service: "ni")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "returns an error response when the backend returns 404" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/sections")
      .to_return(status: 404, body: "{}")

    result = described_class.call(service: "uk")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end
end
