# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigateHierarchyTool do
  let(:base_url) { "https://example.com" }
  let(:gn_response) { File.read("spec/fixtures/api/goods_nomenclature.json") }
  let(:chapter_response) { File.read("spec/fixtures/api/chapter.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "accepts 2-10 digit codes" do
    expect(described_class.input_schema.to_h.dig(:properties, :code, :pattern)).to eq("^\\d{2,10}$")
  end

  it "routes a 2-digit code to the chapters endpoint" do
    stub_request(:get, "#{base_url}/uk/api/v2/chapters/01")
      .to_return(status: 200, body: chapter_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "01", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    parsed = JSON.parse(result.content.first[:text], symbolize_names: true)
    expect(parsed[:type]).to eq("chapter")
    expect(parsed[:code]).to eq("0100000000")
  end

  it "pads a 4-digit heading code to 10 digits for goods nomenclature lookup" do
    stub_request(:get, "#{base_url}/uk/api/v2/goods_nomenclatures/0101000000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "0101", service: nil)

    parsed = JSON.parse(result.content.first[:text], symbolize_names: true)
    expect(parsed[:code]).to eq("0101210000")
  end

  it "passes a 10-digit code to goods nomenclature endpoint unchanged" do
    stub_request(:get, "#{base_url}/uk/api/v2/goods_nomenclatures/0101210000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "0101210000", service: nil)

    parsed = JSON.parse(result.content.first[:text], symbolize_names: true)
    expect(parsed[:code]).to eq("0101210000")
    expect(parsed[:description]).to eq("Horses")
  end

  it "calls the XI endpoint when service is XI" do
    stub_request(:get, "#{base_url}/xi/api/v2/goods_nomenclatures/0101210000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(code: "0101210000", service: "XI")

    expect(result.error?).to be false
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
