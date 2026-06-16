# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCommoditiesTool do
  let(:uk_base_url) { "https://uk.example.com" }
  let(:xi_base_url) { "https://xi.example.com" }
  let(:search_response) { File.read("spec/fixtures/api/search.json") }

  before do
    ENV["TARIFF_UK_API_URL"] = uk_base_url
    ENV["TARIFF_XI_API_URL"] = xi_base_url
  end

  after do
    ENV.delete("TARIFF_UK_API_URL")
    ENV.delete("TARIFF_XI_API_URL")
  end

  it "searches the UK service by default" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/search")
      .with(query: { "q" => "horses" })
      .to_return(status: 200, body: search_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(query: "horses", service: nil)

    expect(result).to include("data")
  end

  it "searches the XI service when service is northern_island" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/search")
      .with(query: { "q" => "horses" })
      .to_return(status: 200, body: search_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(query: "horses", service: "northern_ireland")

    expect(result).to include("data")
  end

  it "raises StandardError on backend API error" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/search")
      .with(query: { "q" => "horses" })
      .to_return(status: 503, body: "{}")

    expect {
      described_class.new.call(query: "horses", service: nil)
    }.to raise_error(StandardError, /Backend API error/)
  end
end
