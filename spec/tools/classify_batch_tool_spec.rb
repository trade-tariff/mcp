# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClassifyBatchTool do
  let(:base_url) { "https://example.com" }

  def body_for(code:, description:, score: 0.5)
    {
      data: [
        {
          type: "classification_search_result",
          id: "1",
          attributes: {
            goods_nomenclature_item_id: code,
            goods_nomenclature_sid: 1,
            description: description,
            declarable: true,
            score: score
          }
        }
      ],
      meta: { retrieval_method: "hybrid", result_count: 1 }
    }.to_json
  end

  def stub_search(query, body)
    stub_request(:get, "#{base_url}/uk/api/v2/classification_search")
      .with(query: hash_including("q" => query))
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  before { ENV["TARIFF_API_URL"] = base_url }
  after { ENV.delete("TARIFF_API_URL") }

  it "describes itself as a shortlist tool and not a bulk classifier" do
    expect(described_class.description).to include("not a bulk classifier")
  end

  it "returns one labelled shortlist per item" do
    stub_search("wireless headphones", body_for(code: "8518300090", description: "Headphones"))
    stub_search("cotton t-shirt", body_for(code: "6109100010", description: "T-shirts of cotton"))

    result = described_class.call(items: [
      { "reference" => "line-1", "query" => "wireless headphones" },
      { "reference" => "line-2", "query" => "cotton t-shirt" }
    ])

    json = JSON.parse(result.content.first[:text], symbolize_names: true)
    expect(json[:batch_size]).to eq(2)
    expect(json[:items].map { |i| i[:reference] }).to eq(%w[line-1 line-2])
    expect(json[:items].map { |i| i[:query] }).to eq([ "wireless headphones", "cotton t-shirt" ])
    expect(json[:items].first[:results].first[:code]).to eq("8518300090")
    expect(json[:items].last[:results].first[:code]).to eq("6109100010")
  end

  it "numbers items that have no reference" do
    stub_search("wireless headphones", body_for(code: "8518300090", description: "Headphones"))

    result = described_class.call(items: [ { "query" => "wireless headphones" } ])

    json = JSON.parse(result.content.first[:text], symbolize_names: true)
    expect(json[:items].first[:reference]).to eq("item_1")
  end

  it "tells the caller that each item still needs the full per-item workflow" do
    stub_search("wireless headphones", body_for(code: "8518300090", description: "Headphones"))

    result = described_class.call(items: [ { "query" => "wireless headphones" } ])

    notice = result.content.last[:text]
    expect(notice).to include("does not classify")
    expect(notice).to include("one item at a time")
    expect(notice).to include("note_mentions")
    expect(notice).to include("Do not compare relative_match")
  end

  it "passes the expanded query, service, and validity date through to each search" do
    stub = stub_request(:get, "#{base_url}/xi/api/v2/classification_search")
      .with(query: { "q" => "headphones", "expanded_query" => "earphones", "limit" => "5", "as_of" => "2026-06-19" })
      .to_return(status: 200, body: body_for(code: "8518300090", description: "Headphones"), headers: { "Content-Type" => "application/json" })

    described_class.call(
      items: [ { "query" => "headphones", "expanded_query" => "earphones" } ],
      limit: 5,
      service: "ni",
      validity_date: "2026-06-19"
    )

    expect(stub).to have_been_requested
  end

  it "records a per-item error and still returns the other items" do
    stub_request(:get, "#{base_url}/uk/api/v2/classification_search")
      .with(query: hash_including("q" => "broken item"))
      .to_return(status: 500, body: "", headers: {})
    stub_search("cotton t-shirt", body_for(code: "6109100010", description: "T-shirts of cotton"))

    result = described_class.call(items: [
      { "query" => "broken item" },
      { "query" => "cotton t-shirt" }
    ])

    json = JSON.parse(result.content.first[:text], symbolize_names: true)
    expect(json[:items].first[:error]).to include("could not be searched")
    expect(json[:items].first).not_to have_key(:results)
    expect(json[:items].last[:results].first[:code]).to eq("6109100010")
  end

  it "stops the whole batch when the API rate limits it" do
    stub_request(:get, "#{base_url}/uk/api/v2/classification_search")
      .with(query: hash_including("q" => "first item"))
      .to_return(status: 429, body: "", headers: {})
    second = stub_search("second item", body_for(code: "6109100010", description: "T-shirts"))

    result = described_class.call(items: [ { "query" => "first item" }, { "query" => "second item" } ])

    expect(result).to be_error
    expect(result.content.first[:text]).to include("Rate limit exceeded")
    expect(second).not_to have_been_requested
  end

  it "rejects an empty item list" do
    result = described_class.call(items: [])

    expect(result).to be_error
    expect(result.content.first[:text]).to include("at least 1")
  end

  it "rejects more items than the batch limit" do
    items = Array.new(11) { |i| { "query" => "item #{i}" } }

    result = described_class.call(items: items)

    expect(result).to be_error
    expect(result.content.first[:text]).to include("at most 10")
  end

  it "rejects an item with a blank query" do
    result = described_class.call(items: [ { "reference" => "line-1", "query" => "  " } ])

    expect(result).to be_error
    expect(result.content.first[:text]).to include("query")
  end

  it "returns an error for an invalid date" do
    result = described_class.call(items: [ { "query" => "headphones" } ], validity_date: "19-06-2026")

    expect(result).to be_error
    expect(result.content.first[:text]).to include("Invalid validity_date")
  end
end
