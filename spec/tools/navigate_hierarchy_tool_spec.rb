# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigateHierarchyTool do
  let(:base_url) { "https://example.com" }
  let(:gn_response) { File.read("spec/fixtures/api/goods_nomenclature.json") }

  it "advertises itself as code navigation after classification search" do
    description = described_class.description

    expect(description).to include("Use after classification_search")
    expect(description).to include("known commodity code")
    expect(description).to include("tariff hierarchy")
  end

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "returns goods nomenclature for UK by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/goods_nomenclatures/0101210000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "0101210000", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "pads a 4-digit heading code to 10 digits" do
    stub_request(:get, "#{base_url}/uk/api/v2/goods_nomenclatures/0101000000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "0101", service: nil)

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "pads an 8-digit subheading code to 10 digits" do
    stub_request(:get, "#{base_url}/uk/api/v2/goods_nomenclatures/8703240000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "87032400", service: nil)

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "calls the XI endpoint when service is XI" do
    stub_request(:get, "#{base_url}/xi/api/v2/goods_nomenclatures/0101210000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "0101210000", service: "XI")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "returns an error response when code is not found" do
    stub_request(:get, "#{base_url}/uk/api/v2/goods_nomenclatures/9999000000")
      .to_return(status: 404, body: "{}")

    result = described_class.call(code: "9999", service: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns an error response for a non-numeric code" do
    result = described_class.call(code: "../../etc/passwd", service: nil)

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid code")
  end
end
