# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchQuotasShaper do
  def api_response(data: [], included: [], meta: {})
    { "data" => data, "included" => included, "meta" => meta }
  end

  def quota(id: "1", order_number_id: "094011", attrs: {})
    {
      "id" => id,
      "type" => "quota_definition",
      "attributes" => {
        "description" => "Beef and veal",
        "status" => "open",
        "balance" => "5000.0",
        "initial_volume" => "10000.0",
        "measurement_unit" => "KGM",
        "measurement_unit_qualifier" => nil,
        "validity_start_date" => "2026-01-01T00:00:00.000Z",
        "validity_end_date" => "2026-12-31T00:00:00.000Z"
      }.merge(attrs),
      "relationships" => {
        "order_number" => { "data" => { "id" => order_number_id, "type" => "order_number" } },
        "measures" => { "data" => [] },
        "quota_order_number_origins" => { "data" => [] }
      }
    }
  end

  def order_number(id: "094011", geo_area_ids: [])
    {
      "id" => id,
      "type" => "order_number",
      "attributes" => { "number" => id },
      "relationships" => {
        "geographical_areas" => {
          "data" => geo_area_ids.map { |gid| { "id" => gid, "type" => "geographical_area" } }
        }
      }
    }
  end

  def geo_area(id:, description:)
    {
      "id" => id,
      "type" => "geographical_area",
      "attributes" => { "geographical_area_id" => id, "description" => description }
    }
  end

  subject(:result) { described_class.call(api_response) }

  it "returns a quotas key with an empty array when there is no data" do
    expect(result[:quotas]).to eq([])
  end

  context "with a single quota" do
    subject(:result) do
      described_class.call(api_response(
        data: [ quota ],
        included: [
          order_number(id: "094011", geo_area_ids: [ "1011" ]),
          geo_area(id: "1011", description: "ERGA OMNES")
        ]
      ))
    end

    it "extracts quota fields" do
      q = result[:quotas].first
      expect(q[:order_number]).to eq("094011")
      expect(q[:description]).to eq("Beef and veal")
      expect(q[:status]).to eq("open")
      expect(q[:balance]).to eq("5000.0")
      expect(q[:initial_volume]).to eq("10000.0")
      expect(q[:measurement_unit]).to eq("KGM")
      expect(q[:validity_start_date]).to eq("2026-01-01")
      expect(q[:validity_end_date]).to eq("2026-12-31")
    end

    it "includes the geographical area" do
      expect(result[:quotas].first[:geographical_areas]).to eq([
        { id: "1011", description: "ERGA OMNES" }
      ])
    end
  end

  context "with a measurement_unit_qualifier" do
    subject(:result) do
      described_class.call(api_response(
        data: [ quota(attrs: { "measurement_unit" => "KGM", "measurement_unit_qualifier" => "Z" }) ],
        included: [ order_number ]
      ))
    end

    it "joins unit and qualifier" do
      expect(result[:quotas].first[:measurement_unit]).to eq("KGM Z")
    end
  end

  context "with pagination meta" do
    subject(:result) do
      described_class.call(api_response(
        meta: { "pagination" => { "page" => 1, "per_page" => 20, "total_count" => 40 } }
      ))
    end

    it "includes pagination in meta" do
      expect(result[:meta][:pagination]["total_count"]).to eq(40)
    end
  end
end
