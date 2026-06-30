# frozen_string_literal: true

require "rails_helper"

RSpec.describe DutyVatCalculatorShaper do
  def api_response(measures: [], vat_measures: [])
    {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => {
          "import_measures" => { "data" => measures.map { |m| { "id" => m["id"], "type" => "measure" } } },
          "export_measures" => { "data" => [] }
        }
      },
      "included" => measures + vat_measures + build_supporting_included(measures, vat_measures)
    }
  end

  def build_supporting_included(measures, vat_measures)
    all = measures + vat_measures
    all.flat_map do |m|
      rels = m["relationships"]
      [
        rels.dig("measure_type", "data"),
        rels.dig("duty_expression", "data"),
        rels.dig("geographical_area", "data")
      ].compact.map { |ref| @index[ref["type"]]&.fetch(ref["id"], nil) }.compact
    end
  end

  let(:erga_geo) do
    { "id" => "1011", "type" => "geographical_area",
      "attributes" => { "geographical_area_id" => "1011", "description" => "ERGA OMNES" } }
  end
  let(:mtype_third) do
    { "id" => "103", "type" => "measure_type",
      "attributes" => { "description" => "Third country duty" } }
  end
  let(:mtype_vat) do
    { "id" => "305", "type" => "measure_type",
      "attributes" => { "description" => "Value added tax" } }
  end
  let(:duty_pct) do
    { "id" => "d1", "type" => "duty_expression",
      "attributes" => { "base" => "12.00 %" } }
  end
  let(:duty_specific) do
    { "id" => "d2", "type" => "duty_expression",
      "attributes" => { "base" => "GBP 1.50 / 100 kg" } }
  end
  let(:duty_vat_standard) do
    { "id" => "d4", "type" => "duty_expression",
      "attributes" => { "base" => "20.00 %" } }
  end
  let(:duty_vat_reduced) do
    { "id" => "d5", "type" => "duty_expression",
      "attributes" => { "base" => "5.00 %" } }
  end

  def measure(id, type_id, duty_id, geo_id, vat: false)
    {
      "id" => id, "type" => "measure",
      "attributes" => { "vat" => vat, "excise" => false, "reduction_indicator" => nil,
                        "effective_start_date" => nil, "effective_end_date" => nil },
      "relationships" => {
        "measure_type"      => { "data" => { "id" => type_id, "type" => "measure_type" } },
        "duty_expression"   => { "data" => { "id" => duty_id, "type" => "duty_expression" } },
        "geographical_area" => { "data" => { "id" => geo_id, "type" => "geographical_area" } },
        "order_number"      => { "data" => nil },
        "measure_conditions"=> { "data" => [] }
      }
    }
  end

  before do
    @index = {
      "measure_type"      => { "103" => mtype_third, "305" => mtype_vat },
      "duty_expression"   => { "d1" => duty_pct, "d2" => duty_specific },
      "geographical_area" => { "1011" => erga_geo }
    }
  end

  let(:pct_measure) { measure("m1", "103", "d1", "1011") }
  let(:vat_measure) { measure("m2", "305", "d4", "1011", vat: true) }
  let(:specific_measure) { measure("m3", "103", "d2", "1011") }
  let(:reduced_vat_measure) { measure("m6", "305", "d5", "1011", vat: true) }

  def full_response(*measures)
    included = measures + [ erga_geo, mtype_third, mtype_vat, duty_pct, duty_specific, duty_vat_standard, duty_vat_reduced ]
    {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => {
          "import_measures" => { "data" => measures.map { |m| { "id" => m["id"], "type" => "measure" } } },
          "export_measures" => { "data" => [] }
        }
      },
      "included" => included.uniq { |x| [ x["type"], x["id"] ] }
    }
  end

  it "returns rates only when no customs_value given" do
    result = described_class.call(full_response(pct_measure), country_code: nil, customs_value: nil)
    m = result[:applicable_measures].find { |x| x[:type] == "Third country duty" }
    expect(m[:rate]).to eq("12.00 %")
    expect(m).not_to have_key(:duty_amount)
  end

  it "calculates duty_amount for ad-valorem duties when customs_value given" do
    result = described_class.call(full_response(pct_measure), country_code: nil, customs_value: 500.0)
    m = result[:applicable_measures].find { |x| x[:type] == "Third country duty" }
    expect(m[:duty_amount]).to eq(60.0)
  end

  it "calculates VAT using the backend's own VAT duty expression rate, not a hard-coded 20%" do
    result = described_class.call(full_response(pct_measure, vat_measure), country_code: nil, customs_value: 500.0)
    vat = result[:applicable_measures].find { |x| x[:vat] }
    expect(vat[:vat_amount]).to eq(112.0)  # (500 + 60) * 0.20, where 20% comes from duty_vat_standard's "20.00 %"
  end

  it "uses a reduced VAT rate when the backend's VAT measure carries one, instead of forcing 20%" do
    result = described_class.call(full_response(pct_measure, reduced_vat_measure), country_code: nil, customs_value: 500.0)
    vat = result[:applicable_measures].find { |x| x[:vat] }
    expect(vat[:rate]).to eq("5.00 %")
    expect(vat[:vat_amount]).to eq(28.0) # (500 + 60) * 0.05
  end

  it "returns specific duties with a calculation_note and no amount" do
    result = described_class.call(full_response(specific_measure), country_code: nil, customs_value: 500.0)
    m = result[:applicable_measures].find { |x| x[:type] == "Third country duty" }
    expect(m[:duty_amount]).to be_nil
    expect(m[:calculation_note]).to include("specific duty")
  end

  it "includes commodity_code and inputs in result" do
    result = described_class.call(full_response(pct_measure), country_code: "CN", customs_value: 100.0)
    expect(result[:commodity_code]).to eq("0101210000")
    expect(result[:inputs][:customs_value]).to eq(100.0)
  end

  it "uses only the country-specific duty_amount (not the sum) as the VAT base when both ERGA OMNES and a country-specific ad-valorem duty apply" do
    cn_geo = { "id" => "40", "type" => "geographical_area",
               "attributes" => { "geographical_area_id" => "CN", "description" => "China" } }
    duty_cn_pct = { "id" => "d3", "type" => "duty_expression",
                     "attributes" => { "base" => "5.00 %" } }

    erga_pct_measure = measure("m1", "103", "d1", "1011")        # 12.00 %, ERGA OMNES
    cn_pct_measure    = measure("m4", "103", "d3", "40")          # 5.00 %, country-specific
    vat_for_cn        = measure("m5", "305", "d4", "40", vat: true)

    included = [ erga_pct_measure, cn_pct_measure, vat_for_cn, erga_geo, cn_geo, mtype_third,
                mtype_vat, duty_pct, duty_specific, duty_cn_pct, duty_vat_standard ]
    response = {
      "data" => {
        "attributes" => { "goods_nomenclature_item_id" => "0101210000" },
        "relationships" => {
          "import_measures" => {
            "data" => [ erga_pct_measure, cn_pct_measure, vat_for_cn ].map { |m| { "id" => m["id"], "type" => "measure" } }
          },
          "export_measures" => { "data" => [] }
        }
      },
      "included" => included.uniq { |x| [ x["type"], x["id"] ] }
    }

    result = described_class.call(response, country_code: "CN", customs_value: 500.0)

    erga_measure = result[:applicable_measures].find { |m| m[:rate] == "12.00 %" }
    cn_measure   = result[:applicable_measures].find { |m| m[:rate] == "5.00 %" }
    vat_measure  = result[:applicable_measures].find { |m| m[:vat] }

    expect(erga_measure[:duty_amount]).to eq(60.0)
    expect(cn_measure[:duty_amount]).to eq(25.0)
    # VAT base should be customs_value + country-specific duty (25.0), not + 85.0 (sum)
    expect(vat_measure[:vat_amount]).to eq(105.0) # (500 + 25) * 0.20
  end

  it "returns the VAT rate from the backend's duty expression even when no customs_value given" do
    result = described_class.call(full_response(vat_measure), country_code: nil, customs_value: nil)
    vat = result[:applicable_measures].find { |x| x[:vat] }
    expect(vat[:rate]).to eq("20.00 %")
    expect(vat).not_to have_key(:vat_amount)
  end

  it "strips the internal geo_id field from every applicable measure" do
    result = described_class.call(full_response(pct_measure, vat_measure), country_code: nil, customs_value: 500.0)

    result[:applicable_measures].each do |measure|
      expect(measure).not_to have_key(:geo_id)
    end
  end
end
