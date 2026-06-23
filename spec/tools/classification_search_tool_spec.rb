# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClassificationSearchTool do
  let(:base_url) { "https://example.com" }
  let(:response_body) do
    {
      data: [
        {
          type: "classification_search_result",
          id: "123",
          attributes: {
            goods_nomenclature_item_id: "8518300090",
            goods_nomenclature_sid: 123,
            description: "Headphones and earphones",
            declarable: true,
            score: 0.03125
          }
        }
      ],
      meta: {
        request_id: "request-1",
        retrieval_method: "hybrid",
        result_count: 1
      }
    }.to_json
  end

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "advertises itself as the starting point for product classification" do
    expect(described_class.title).to include("Classify a product")

    description = described_class.description

    expect(description).to include("First tool")
    expect(description).to include("classifying")
    expect(description).to include("natural-language product description")
    expect(description).to include("commodity lookup")
    expect(description).to include("commodity code")
    expect(description).to include("HS code")
    expect(description).to include("tariff classification")
  end

  it "calls the UK classification search endpoint" do
    stub_request(:get, "#{base_url}/uk/api/v2/classification_search")
      .with(query: { "q" => "wireless headphones", "limit" => "5" })
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(query: "wireless headphones", limit: 5, service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data", "meta")
  end

  it "passes optional date and expanded query" do
    stub = stub_request(:get, "#{base_url}/uk/api/v2/classification_search")
      .with(query: { "q" => "wireless headphones", "expanded_query" => "bluetooth headphones", "as_of" => "2026-06-19" })
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(query: "wireless headphones", expanded_query: "bluetooth headphones", validity_date: "2026-06-19", service: "uk")

    expect(stub).to have_been_requested
  end

  it "returns an error for an invalid date" do
    result = described_class.call(query: "wireless headphones", validity_date: "19-06-2026")

    expect(result).to be_error
    expect(result.content.first[:text]).to include("Invalid validity_date")
  end

  it "returns an error for an invalid limit" do
    result = described_class.call(query: "wireless headphones", limit: 0)

    expect(result).to be_error
    expect(result.content.first[:text]).to include("Invalid limit")
  end
end
