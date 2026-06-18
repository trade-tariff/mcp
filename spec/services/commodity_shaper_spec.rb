# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityShaper do
  def api_response(data_attrs: {}, included: [], relationships: {})
    default_rels = {
      "footnotes" => { "data" => [] },
      "section" => { "data" => nil },
      "chapter" => { "data" => nil },
      "heading" => { "data" => nil },
      "import_measures" => { "data" => [] },
      "export_measures" => { "data" => [] }
    }
    {
      "data" => {
        "id" => "1",
        "type" => "commodity",
        "attributes" => {
          "goods_nomenclature_item_id" => "0101210000",
          "description_plain" => "Pure-bred breeding animals",
          "declarable" => true,
          "validity_start_date" => "2012-01-01T00:00:00.000Z",
          "validity_end_date" => nil,
          "basic_duty_rate" => "0.00 %"
        }.merge(data_attrs),
        "relationships" => default_rels.merge(relationships)
      },
      "included" => included
    }
  end

  subject(:result) { described_class.call(api_response) }

  it "extracts top-level commodity fields" do
    expect(result[:commodity_code]).to eq("0101210000")
    expect(result[:description]).to eq("Pure-bred breeding animals")
    expect(result[:declarable]).to be(true)
    expect(result[:validity_start_date]).to eq("2012-01-01")
    expect(result[:validity_end_date]).to be_nil
    expect(result[:basic_duty_rate]).to eq("0.00 %")
  end

  it "truncates validity_start_date to YYYY-MM-DD" do
    response = api_response(data_attrs: { "validity_start_date" => "2021-01-01T00:00:00.000Z" })
    expect(described_class.call(response)[:validity_start_date]).to eq("2021-01-01")
  end

  context "with a section in included" do
    let(:section) { { "id" => "1", "type" => "section", "attributes" => { "title" => "Live animals; animal products" } } }
    let(:response) do
      api_response(
        relationships: { "section" => { "data" => { "id" => "1", "type" => "section" } } },
        included: [ section ]
      )
    end

    it "resolves the section title" do
      expect(described_class.call(response)[:section]).to eq("Live animals; animal products")
    end
  end

  context "with a chapter that uses formatted_description" do
    let(:chapter) do
      { "id" => "27623", "type" => "chapter", "attributes" => { "formatted_description" => "Live animals" } }
    end
    let(:response) do
      api_response(
        relationships: { "chapter" => { "data" => { "id" => "27623", "type" => "chapter" } } },
        included: [ chapter ]
      )
    end

    it "falls back to formatted_description when description_plain is absent" do
      expect(described_class.call(response)[:chapter]).to eq("Live animals")
    end
  end

  context "with import measures" do
    let(:measure_type) { { "id" => "103", "type" => "measure_type", "attributes" => { "description" => "Third country duty" } } }
    let(:duty_expr)    { { "id" => "20000000-duty_expression", "type" => "duty_expression", "attributes" => { "base" => "0.00 %" } } }
    let(:geo_area)     { { "id" => "1011", "type" => "geographical_area", "attributes" => { "id" => "1011", "description" => "ERGA OMNES", "geographical_area_id" => "1011" } } }
    let(:measure) do
      {
        "id" => "20000000",
        "type" => "measure",
        "attributes" => { "import" => true, "export" => false, "effective_start_date" => "2021-01-01T00:00:00.000Z", "effective_end_date" => nil },
        "relationships" => {
          "measure_type" => { "data" => { "id" => "103", "type" => "measure_type" } },
          "duty_expression" => { "data" => { "id" => "20000000-duty_expression", "type" => "duty_expression" } },
          "geographical_area" => { "data" => { "id" => "1011", "type" => "geographical_area" } },
          "measure_conditions" => { "data" => [] }
        }
      }
    end
    let(:response) do
      api_response(
        relationships: { "import_measures" => { "data" => [ { "id" => "20000000", "type" => "measure" } ] } },
        included: [ measure, measure_type, duty_expr, geo_area ]
      )
    end

    subject(:shaped) { described_class.call(response) }

    it "resolves measure type, duty, and geographical area" do
      m = shaped[:import_measures].first
      expect(m[:type]).to eq("Third country duty")
      expect(m[:duty]).to eq("0.00 %")
      expect(m[:geographical_area]).to eq("ERGA OMNES (1011)")
      expect(m[:effective_start_date]).to eq("2021-01-01")
    end

    it "omits the import/export boolean flags" do
      m = shaped[:import_measures].first
      expect(m).not_to have_key(:import)
      expect(m).not_to have_key(:export)
    end

    it "omits conditions key when there are none" do
      expect(shaped[:import_measures].first).not_to have_key(:conditions)
    end
  end

  context "with measure conditions" do
    let(:condition) do
      {
        "id" => "123",
        "type" => "measure_condition",
        "attributes" => {
          "condition" => "B: Presentation of a certificate/licence/document",
          "document_code" => "C640",
          "requirement" => "Common Health Entry Document",
          "action" => "Import/export allowed after control",
          "guidance_cds" => "huge html blob that should be dropped"
        },
        "relationships" => { "measure_condition_components" => { "data" => [] } }
      }
    end
    let(:measure) do
      {
        "id" => "1",
        "type" => "measure",
        "attributes" => { "import" => true, "export" => false, "effective_start_date" => nil, "effective_end_date" => nil },
        "relationships" => {
          "measure_type" => { "data" => nil },
          "duty_expression" => { "data" => nil },
          "geographical_area" => { "data" => nil },
          "measure_conditions" => { "data" => [ { "id" => "123", "type" => "measure_condition" } ] }
        }
      }
    end
    let(:response) do
      api_response(
        relationships: { "import_measures" => { "data" => [ { "id" => "1", "type" => "measure" } ] } },
        included: [ measure, condition ]
      )
    end

    it "includes condition, document_code, requirement, and action" do
      c = described_class.call(response)[:import_measures].first[:conditions].first
      expect(c[:condition]).to eq("B: Presentation of a certificate/licence/document")
      expect(c[:document_code]).to eq("C640")
      expect(c[:requirement]).to eq("Common Health Entry Document")
      expect(c[:action]).to eq("Import/export allowed after control")
    end

    it "does not include guidance_cds" do
      c = described_class.call(response)[:import_measures].first[:conditions].first
      expect(c).not_to have_key(:guidance_cds)
    end
  end

  context "with footnotes" do
    let(:footnote) do
      { "id" => "NC018", "type" => "footnote", "attributes" => { "code" => "NC018", "description" => "Entry subject to conditions." } }
    end
    let(:response) do
      api_response(
        relationships: { "footnotes" => { "data" => [ { "id" => "NC018", "type" => "footnote" } ] } },
        included: [ footnote ]
      )
    end

    it "includes footnote code and description" do
      fn = described_class.call(response)[:footnotes].first
      expect(fn[:code]).to eq("NC018")
      expect(fn[:description]).to eq("Entry subject to conditions.")
    end
  end
end
