# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClassificationSearchShaper do
  def api_response(results: [])
    {
      "data" => results,
      "meta" => { "request_id" => "req-1", "retrieval_method" => "hybrid", "result_count" => results.length }
    }
  end

  def result_item(item_id: "8518300090", sid: 123, description: "Headphones", declarable: true, score: 0.03125)
    {
      "type" => "classification_search_result",
      "id" => sid.to_s,
      "attributes" => {
        "goods_nomenclature_item_id" => item_id,
        "goods_nomenclature_sid" => sid,
        "description" => description,
        "declarable" => declarable,
        "score" => score
      }
    }
  end

  it "extracts code, sid, description, declarable, score, and relative match from each result" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw, query: "headphones")

    expect(output[:results]).to eq([
      {
        code: "8518300090",
        sid: 123,
        description: "Headphones",
        declarable: true,
        score: 0.03125,
        relative_match: { band: "high", ratio_to_top_result: 1.0 }
      }
    ])
  end

  it "echoes the query that produced the results" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw, query: "wireless headphones")

    expect(output[:query]).to eq("wireless headphones")
  end

  it "echoes the expanded query when one was used" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw, query: "headphones", expanded_query: "bluetooth earphones")

    expect(output[:expanded_query]).to eq("bluetooth earphones")
  end

  it "omits the expanded query when none was used" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw, query: "headphones")

    expect(output).not_to have_key(:expanded_query)
  end

  it "omits the query when the caller does not supply one" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw)

    expect(output).not_to have_key(:query)
  end

  it "includes a relative_match_note that rules out comparison between queries" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw, query: "headphones")

    expect(output[:relative_match_note]).to include("not a probability")
    expect(output[:relative_match_note]).to include("not comparable")
  end

  it "bands the relative match against the top score in this result set" do
    raw = api_response(results: [
      result_item(item_id: "1111111111", sid: 1, score: 1.0),
      result_item(item_id: "2222222222", sid: 2, score: 0.9),
      result_item(item_id: "3333333333", sid: 3, score: 0.6),
      result_item(item_id: "4444444444", sid: 4, score: 0.1)
    ])
    output = described_class.call(raw, query: "headphones")

    expect(output[:results].map { |r| r[:relative_match][:band] }).to eq(%w[high high medium low])
  end

  it "reports the ratio to the top result alongside the band" do
    raw = api_response(results: [
      result_item(item_id: "1111111111", sid: 1, score: 1.0),
      result_item(item_id: "2222222222", sid: 2, score: 0.5)
    ])
    output = described_class.call(raw, query: "headphones")

    expect(output[:results].map { |r| r[:relative_match][:ratio_to_top_result] }).to eq([ 1.0, 0.5 ])
  end

  it "includes meta fields" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw, query: "headphones")

    expect(output[:retrieval_method]).to eq("hybrid")
    expect(output[:result_count]).to eq(1)
  end

  it "returns an empty results array when data is absent" do
    output = described_class.call({})
    expect(output[:results]).to eq([])
  end

  it "omits score and relative match when the score is nil" do
    raw = api_response(results: [ result_item(score: nil) ])
    output = described_class.call(raw, query: "headphones")

    expect(output[:results].first).not_to have_key(:score)
    expect(output[:results].first).not_to have_key(:relative_match)
  end
end
