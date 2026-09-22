# frozen_string_literal: true

require "rails_helper"

RSpec.describe LookupCommodityTool do
  let(:base_url) { "https://example.com" }
  let(:commodity_response) { File.read("spec/fixtures/api/commodity.json") }

  it "advertises itself as a tool for looking up 10-digit commodity codes" do
    description = described_class.description

    expect(description).to include("10-digit commodity code")
    expect(description).to include("commodity code")
    expect(description).to include("measures")
  end

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "returns commodity details for UK by default" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("commodity_code")
  end

  it "calls the XI endpoint when service is xi" do
    stub_request(:get, /xi\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", service: "xi")

    expect(JSON.parse(result.content.first[:text])).to include("commodity_code")
  end

  it "sends sparse field and include params to the API" do
    stub = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
             .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000", service: nil)

    expect(stub).to have_been_requested
    expect(stub.with { |req| req.uri.query }.to_s).to be_truthy
  end

  it "returns an error response when commodity is not found" do
    stub_request(:get, /uk\/api\/v2\/commodities\/9999999999/)
      .to_return(status: 404, body: "{}")

    result = described_class.call(commodity_code: "9999999999", service: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns an error response for a non-numeric commodity_code" do
    result = described_class.call(commodity_code: "../../etc/passwd", service: nil)

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid commodity_code")
  end

  it "raises StandardError for an unrecognised service" do
    expect {
      described_class.call(commodity_code: "0101210000", service: "germany")
    }.to raise_error(StandardError, /Unknown service/)
  end

  context "when measures_only: true" do
    it "calls the commodity endpoint with measures include and uses CommodityMeasuresShaper" do
      stub_request(:get, "#{base_url}/uk/api/v2/commodities/0101210000")
        .with(query: hash_including("include" => a_string_including("import_measures")))
        .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

      result = described_class.call(commodity_code: "0101210000", measures_only: true)

      expect(result.error?).to be false
    end

    it "passes country_code as filter when measures_only and country_code provided" do
      stub = stub_request(:get, "#{base_url}/uk/api/v2/commodities/0101210000")
        .with(query: hash_including("filter.geographical_area_id" => "CN"))
        .to_return(status: 200, body: commodity_response, headers: { "Content-Type" => "application/json" })

      described_class.call(commodity_code: "0101210000", measures_only: true, country_code: "CN")

      expect(stub).to have_been_requested
    end

    it "returns an error for an invalid direction" do
      result = described_class.call(commodity_code: "0101210000", measures_only: true, direction: "sideways")

      expect(result.error?).to be true
      expect(result.content.first[:text]).to include("Invalid direction")
    end
  end

  describe "measure footnotes" do
    it "requests import and export measure footnotes in the full lookup" do
      expect(described_class::FULL_INCLUDE).to include("import_measures.footnotes")
      expect(described_class::FULL_INCLUDE).to include("export_measures.footnotes")
    end

    it "requests import and export measure footnotes in the measures-only lookup" do
      expect(described_class::MEASURES_INCLUDE).to include("import_measures.footnotes")
      expect(described_class::MEASURES_INCLUDE).to include("export_measures.footnotes")
    end

    it "asks for the footnotes field on each measure in the full lookup" do
      expect(described_class.send(:build_full_params)["fields[measure]"]).to include("footnotes")
    end
  end

  it "tells the caller that effective_start_date may be a reissue date" do
    expect(described_class.description).to include("reissued")
  end

  describe "measure additional codes and conditional duties" do
    it "requests the additional code on import and export measures" do
      expect(described_class::FULL_INCLUDE).to include("import_measures.additional_code")
      expect(described_class::FULL_INCLUDE).to include("export_measures.additional_code")
      expect(described_class::MEASURES_INCLUDE).to include("import_measures.additional_code")
      expect(described_class::MEASURES_INCLUDE).to include("export_measures.additional_code")
    end

    it "asks for the additional code field on each measure in the full lookup" do
      expect(described_class.send(:build_full_params)["fields[measure]"]).to include("additional_code")
    end

    it "asks for the code on each additional code in the full lookup" do
      expect(described_class.send(:build_full_params)["fields[additional_code]"]).to include("code")
    end

    it "asks for the duty expression on each measure condition in the full lookup" do
      expect(described_class.send(:build_full_params)["fields[measure_condition]"]).to include("duty_expression")
    end
  end
end
