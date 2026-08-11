# frozen_string_literal: true

require "rails_helper"

RSpec.describe NavigateHierarchyShaper do
  describe "goods_nomenclature response" do
    def gn_response(attrs: {}, children: [])
      {
        "data" => {
          "id" => "0101210000",
          "type" => "goods_nomenclature",
          "attributes" => {
            "goods_nomenclature_item_id" => "0101210000",
            "description" => "Horses",
            "number_indents" => 3
          }.merge(attrs),
          "relationships" => {
            "children" => { "data" => children }
          }
        },
        "included" => children
      }
    end

    it "extracts code, description and indent" do
      output = described_class.call(gn_response)
      expect(output[:code]).to eq("0101210000")
      expect(output[:description]).to eq("Horses")
      expect(output[:indent]).to eq(3)
    end

    it "returns an empty children array when none are present" do
      output = described_class.call(gn_response)
      expect(output[:children]).to eq([])
    end

    it "extracts children when present" do
      child = {
        "id" => "0101210010",
        "type" => "goods_nomenclature",
        "attributes" => {
          "goods_nomenclature_item_id" => "0101210010",
          "description" => "Pure-bred breeding animals",
          "number_indents" => 4
        }
      }
      output = described_class.call(gn_response(
        children: [ { "type" => "goods_nomenclature", "id" => "0101210010" } ]
      ).merge("included" => [ child ]))
      expect(output[:children].length).to eq(1)
      expect(output[:children].first[:code]).to eq("0101210010")
    end
  end

  describe "chapter response" do
    def chapter_response(attrs: {}, headings: [])
      {
        "data" => {
          "id" => "01",
          "type" => "chapter",
          "attributes" => {
            "goods_nomenclature_item_id" => "0100000000",
            "description" => "LIVE ANIMALS",
            "formatted_description" => "Live animals"
          }.merge(attrs),
          "relationships" => {
            "headings" => { "data" => headings }
          }
        },
        "included" => headings
      }
    end

    it "extracts code, description and type=chapter" do
      output = described_class.call(chapter_response)
      expect(output[:code]).to eq("0100000000")
      expect(output[:description]).to eq("Live animals")
      expect(output[:type]).to eq("chapter")
    end

    it "returns empty headings when none present" do
      output = described_class.call(chapter_response)
      expect(output[:headings]).to eq([])
    end
  end
end
