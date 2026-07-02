# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeographicalAreasShaper do
  def api_response(areas = [])
    {
      "data" => areas,
      "included" => []
    }
  end

  def area(id:, description:)
    {
      "id" => id,
      "type" => "geographical_area",
      "attributes" => {
        "geographical_area_id" => id,
        "description" => description
      }
    }
  end

  subject(:result) { described_class.call(api_response(areas)) }

  context "with a normal list of areas" do
    let(:areas) { [ area(id: "TR", description: "Turkey"), area(id: "GB", description: "United Kingdom") ] }

    it "returns a flat array of id/description pairs" do
      expect(result).to eq([
        { id: "TR", description: "Turkey" },
        { id: "GB", description: "United Kingdom" }
      ])
    end
  end

  context "when data is absent" do
    subject(:result) { described_class.call({}) }

    it "returns an empty array" do
      expect(result).to eq([])
    end
  end

  context "when an area uses the fallback id attribute instead of geographical_area_id" do
    let(:areas) do
      [
        {
          "id" => "1011",
          "type" => "geographical_area",
          "attributes" => { "id" => "1011", "description" => "ERGA OMNES" }
        }
      ]
    end

    it "falls back to the id attribute" do
      expect(result.first[:id]).to eq("1011")
    end
  end
end
