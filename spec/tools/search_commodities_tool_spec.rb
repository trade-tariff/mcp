# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchCommoditiesTool do
  let(:base_url) { "https://example.com" }
  let(:search_response) { File.read("spec/fixtures/api/search.json") }

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "searches the UK service by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/search")
      .with(query: { "q" => "horses" })
      .to_return(status: 200, body: search_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(query: "horses", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("goods_nomenclature_matches")
  end

  it "searches the XI service when service is northern_ireland" do
    stub_request(:get, "#{base_url}/xi/api/v2/search")
      .with(query: { "q" => "horses" })
      .to_return(status: 200, body: search_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(query: "horses", service: "northern_ireland")

    expect(JSON.parse(result.content.first[:text])).to include("goods_nomenclature_matches")
  end

  it "raises StandardError on backend API error" do
    stub_request(:get, "#{base_url}/uk/api/v2/search")
      .with(query: { "q" => "horses" })
      .to_return(status: 503, body: "{}")

    expect { described_class.call(query: "horses", service: nil) }.to raise_error(StandardError, /Backend API error/)
  end
end
