# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeadingShaper do
  def api_response(data_attrs: {}, relationships: {}, included: [])
    default_rels = {
      "footnotes"   => { "data" => [] },
      "section"     => { "data" => nil },
      "chapter"     => { "data" => nil },
      "commodities" => { "data" => [] }
    }
    {
      "data" => {
        "id" => "0101",
        "type" => "heading",
        "attributes" => {
          "goods_nomenclature_item_id" => "0101000000",
          "description_plain" => "Live horses, asses, mules and hinnies",
          "declarable" => false,
          "validity_start_date" => "1972-01-01T00:00:00.000Z",
          "validity_end_date" => nil
        }.merge(data_attrs),
        "relationships" => default_rels.merge(relationships)
      },
      "included" => included
    }
  end

  subject(:result) { described_class.call(api_response) }

  it "extracts top-level heading fields" do
    expect(result[:heading_code]).to eq("0101000000")
    expect(result[:description]).to eq("Live horses, asses, mules and hinnies")
    expect(result[:declarable]).to be(false)
    expect(result[:validity_start_date]).to eq("1972-01-01")
    expect(result[:validity_end_date]).to be_nil
  end

  it "omits nil values" do
    expect(result).not_to have_key(:validity_end_date)
    expect(result).not_to have_key(:section)
    expect(result).not_to have_key(:chapter)
  end

  context "with a linked section" do
    subject(:result) do
      described_class.call(api_response(
        relationships: { "section" => { "data" => { "type" => "section", "id" => "1" } } },
        included: [
          { "id" => "1", "type" => "section", "attributes" => { "title" => "Live animals" } }
        ]
      ))
    end

    it "includes the section title" do
      expect(result[:section]).to eq("Live animals")
    end
  end

  context "with a linked chapter using formatted_description" do
    subject(:result) do
      described_class.call(api_response(
        relationships: { "chapter" => { "data" => { "type" => "chapter", "id" => "01" } } },
        included: [
          { "id" => "01", "type" => "chapter", "attributes" => { "formatted_description" => "Live animals" } }
        ]
      ))
    end

    it "uses formatted_description as chapter text" do
      expect(result[:chapter]).to eq("Live animals")
    end
  end

  context "with declarable commodity children" do
    subject(:result) do
      described_class.call(api_response(
        relationships: {
          "commodities" => { "data" => [
            { "type" => "commodity", "id" => "c1" },
            { "type" => "commodity", "id" => "c2" }
          ] }
        },
        included: [
          {
            "id" => "c1", "type" => "commodity",
            "attributes" => { "goods_nomenclature_item_id" => "0101210000", "description_plain" => "Purebred", "declarable" => true }
          },
          {
            "id" => "c2", "type" => "commodity",
            "attributes" => { "goods_nomenclature_item_id" => "0101290000", "description_plain" => "Other", "declarable" => false }
          }
        ]
      ))
    end

    it "includes only declarable commodities" do
      expect(result[:commodities].length).to eq(1)
      expect(result[:commodities].first[:code]).to eq("0101210000")
      expect(result[:commodities].first[:description]).to eq("Purebred")
    end
  end

  context "with footnotes" do
    subject(:result) do
      described_class.call(api_response(
        relationships: {
          "footnotes" => { "data" => [ { "type" => "footnote", "id" => "f1" } ] }
        },
        included: [
          { "id" => "f1", "type" => "footnote", "attributes" => { "code" => "TN701", "description" => "Some note" } }
        ]
      ))
    end

    it "includes footnote code and description" do
      expect(result[:footnotes]).to eq([ { code: "TN701", description: "Some note" } ])
    end
  end
end
