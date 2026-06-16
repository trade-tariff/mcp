# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigateHierarchyTool do
  let(:uk_base_url) { "https://uk.example.com" }
  let(:xi_base_url) { "https://xi.example.com" }
  let(:gn_response) { File.read("spec/fixtures/api/goods_nomenclature.json") }

  before do
    ENV["TARIFF_UK_API_URL"] = uk_base_url
    ENV["TARIFF_XI_API_URL"] = xi_base_url
  end

  after do
    ENV.delete("TARIFF_UK_API_URL")
    ENV.delete("TARIFF_XI_API_URL")
  end

  it "returns goods nomenclature for UK by default" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/goods_nomenclatures/0101210000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(code: "0101210000", service: nil)

    expect(result).to include("data")
  end

  it "accepts a 4-digit heading code" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/goods_nomenclatures/0101")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(code: "0101", service: nil)

    expect(result).to include("data")
  end

  it "calls the XI endpoint when service is XI" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/goods_nomenclatures/0101210000")
      .to_return(status: 200, body: gn_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(code: "0101210000", service: "XI")

    expect(result).to include("data")
  end

  it "raises StandardError when code is not found" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/goods_nomenclatures/9999")
      .to_return(status: 404, body: "{}")

    expect {
      described_class.new.call(code: "9999", service: nil)
    }.to raise_error(StandardError, /Not found/)
  end
end
