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

    result = described_class.new.call(service: nil)

    expect(result).to include("data")
  end

  it "calls the UK sections endpoint when service is uk" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/sections")
      .to_return(status: 200, body: sections_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(service: "uk")

    expect(result).to include("data")
  end

  it "calls the XI sections endpoint when service is ni" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/sections")
      .to_return(status: 200, body: sections_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(service: "ni")

    expect(result).to include("data")
  end

  it "raises StandardError when the backend returns 404" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/sections")
      .to_return(status: 404, body: "{}")

    expect { described_class.new.call(service: "uk") }.to raise_error(StandardError, /Not found/)
  end
end
