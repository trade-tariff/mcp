# frozen_string_literal: true

require "rails_helper"

RSpec.describe FullTextSearchTool do
  let(:base_url) { "https://example.com" }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  # Matches the actual backend response shape from Api::V2::SearchController#search
  # (verified in app/engines/v2_api.rb and spec/requests/api/v2/search_controller_search_spec.rb
  # in the backend repo): a single JSONAPI resource, not a collection.
  let(:search_body) do
    {
      "data" => {
        "id" => "1",
        "type" => "fuzzy_search",
        "attributes" => {
          "type" => "fuzzy_match",
          "goods_nomenclature_match" => {
            "chapters" => [],
            "headings" => [],
            "commodities" => [
              { "_score" => 4.2, "_source" => { "goods_nomenclature_item_id" => "0101210000", "description" => "Horses, pure-bred breeding animals" } }
            ]
          },
          "reference_match" => { "chapters" => [], "headings" => [], "commodities" => [] }
        }
      }
    }.to_json
  end

  it "calls the search endpoint with the query param" do
    stub = stub_request(:get, "#{base_url}/uk/api/search")
             .with(query: hash_including("q" => "hydraulic"))
             .to_return(status: 200, body: search_body, headers: { "Content-Type" => "application/json" })

    described_class.call(query: "hydraulic")

    expect(stub).to have_been_requested
  end

  it "returns a response with query and results keys" do
    stub_request(:get, "#{base_url}/uk/api/search")
      .with(query: { "q" => "hydraulic" })
      .to_return(status: 200, body: search_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(query: "hydraulic")
    parsed = JSON.parse(result.content.first[:text])

    expect(parsed).to include("query", "results")
    expect(parsed["results"]).to eq(
      [ { "kind" => "commodity", "code" => "0101210000", "description" => "Horses, pure-bred breeding animals" } ]
    )
  end

  it "returns an error when query is blank" do
    result = described_class.call(query: "")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("query")
  end

  it "calls the XI endpoint when service is xi" do
    stub_request(:get, "#{base_url}/xi/api/search")
      .with(query: { "q" => "hydraulic" })
      .to_return(status: 200, body: search_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(query: "hydraulic", service: "xi")
    expect(result).to be_a(MCP::Tool::Response)
  end

  it "returns an error for search_type notes since the backend has no legal-notes search endpoint" do
    result = described_class.call(query: "hydraulic", search_type: "notes")

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("notes")
  end
end
