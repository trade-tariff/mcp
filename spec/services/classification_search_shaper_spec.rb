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

  it "extracts code, sid, description, declarable, score, and confidence from each result" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw)

    expect(output[:results]).to eq([
      { code: "8518300090", sid: 123, description: "Headphones", declarable: true, score: 0.03125, confidence: "high" }
    ])
  end

  it "includes a confidence_note explaining what confidence means" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw)

    expect(output[:confidence_note]).to include("not a calibrated probability")
  end

  it "bands confidence relative to the top score in this result set" do
    raw = api_response(results: [
      result_item(item_id: "1111111111", sid: 1, score: 1.0),
      result_item(item_id: "2222222222", sid: 2, score: 0.9),
      result_item(item_id: "3333333333", sid: 3, score: 0.6),
      result_item(item_id: "4444444444", sid: 4, score: 0.1)
    ])
    output = described_class.call(raw)

    expect(output[:results].map { |r| r[:confidence] }).to eq(%w[high high medium low])
  end

  it "includes meta fields" do
    raw = api_response(results: [ result_item ])
    output = described_class.call(raw)

    expect(output[:retrieval_method]).to eq("hybrid")
    expect(output[:result_count]).to eq(1)
  end

  it "returns an empty results array when data is absent" do
    output = described_class.call({})
    expect(output[:results]).to eq([])
  end

  it "omits score when nil" do
    raw = api_response(results: [ result_item(score: nil) ])
    output = described_class.call(raw)
    expect(output[:results].first).not_to have_key(:score)
  end
end
