# frozen_string_literal: true

require "rails_helper"

RSpec.describe FullTextSearchShaper do
  # The backend /api/search endpoint (Api::V2::SearchController#search) returns a single
  # JSONAPI resource (not a collection) shaped as:
  #   { "data" => { "id" => ..., "type" => "fuzzy_search"|"exact_search"|"null_search",
  #                 "attributes" => { "type" => "fuzzy_match"|"exact_match"|"null_match",
  #                                   "goods_nomenclature_match" => { "chapters" => [...], "headings" => [...], "commodities" => [...] },
  #                                   "reference_match" => { "chapters" => [...], "headings" => [...], "commodities" => [...] },
  #                                   "entry" => { "endpoint" => "chapters", "id" => "01" } } } }
  # Hits inside goods_nomenclature_match/reference_match arrays are raw OpenSearch hits:
  #   { "_score" => 1.23, "_source" => { "goods_nomenclature_item_id" => "0101210000", "description" => "Horses" } }
  # There is no legal-notes search endpoint, so the shaper only ever produces kind: "commodity" results.

  def hit(item_id, description, score = 1.0)
    { "_score" => score, "_source" => { "goods_nomenclature_item_id" => item_id, "description" => description } }
  end

  describe "fuzzy match response" do
    let(:api_response) do
      {
        "data" => {
          "id" => "1",
          "type" => "fuzzy_search",
          "attributes" => {
            "type" => "fuzzy_match",
            "goods_nomenclature_match" => {
              "chapters" => [],
              "headings" => [],
              "commodities" => [ hit("0101210000", "Horses, pure-bred breeding animals", 4.2) ]
            },
            "reference_match" => {
              "chapters" => [],
              "headings" => [],
              "commodities" => []
            }
          }
        }
      }
    end

    it "returns results tagged with kind: commodity for commodity hits" do
      result = described_class.call(api_response, query: "horse", search_type: "descriptions")

      expect(result[:results]).to include(
        { kind: "commodity", code: "0101210000", description: "Horses, pure-bred breeding animals" }
      )
    end

    it "includes query and search_type in the result" do
      result = described_class.call(api_response, query: "horse", search_type: "descriptions")

      expect(result[:query]).to eq("horse")
      expect(result[:search_type]).to eq("descriptions")
    end
  end

  describe "no matches" do
    let(:api_response) do
      {
        "data" => {
          "id" => "1",
          "type" => "null_search",
          "attributes" => {
            "type" => "null_match",
            "goods_nomenclature_match" => { "chapters" => [], "headings" => [], "commodities" => [] },
            "reference_match" => { "chapters" => [], "headings" => [], "commodities" => [] }
          }
        }
      }
    end

    it "returns empty results array when no hits" do
      result = described_class.call(api_response, query: "zzz_no_match", search_type: "descriptions")

      expect(result[:results]).to eq([])
    end
  end

  describe "exact match response" do
    let(:api_response) do
      {
        "data" => {
          "id" => "1",
          "type" => "exact_search",
          "attributes" => {
            "type" => "exact_match",
            "entry" => { "endpoint" => "chapters", "id" => "01" }
          }
        }
      }
    end

    it "returns empty results since exact matches carry no description text to surface" do
      result = described_class.call(api_response, query: "01", search_type: "descriptions")

      expect(result[:results]).to eq([])
    end
  end

  describe "notes search_type" do
    it "raises because no legal-notes search endpoint exists in the backend" do
      expect do
        described_class.call({ "data" => nil }, query: "horse", search_type: "notes")
      end.to raise_error(FullTextSearchShaper::UnsupportedSearchType)
    end
  end
end
