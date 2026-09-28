# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityHistoryDiffTool do
  let(:base_url) { "https://example.com" }
  let(:commodity_body) { File.read("spec/fixtures/api/commodity.json") }

  before { ENV["TARIFF_API_URL"] = base_url }
  after  { ENV.delete("TARIFF_API_URL") }

  it "tells the caller that a snapshot for any date after today can still change" do
    expect(described_class.description).to include("any date after today")
    expect(described_class.description).not_to include("provisional")
  end

  it "makes two commodity requests (one per date)" do
    stub_from = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
                  .with(query: hash_including("as_of" => "2024-01-01"))
                  .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })
    stub_to   = stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
                  .with(query: hash_including("as_of" => "2025-01-01"))
                  .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    described_class.call(commodity_code: "0101210000", from_date: "2024-01-01", to_date: "2025-01-01")

    expect(stub_from).to have_been_requested
    expect(stub_to).to have_been_requested
  end

  it "returns a response with changes key" do
    stub_request(:get, /uk\/api\/v2\/commodities\/0101210000/)
      .to_return(status: 200, body: commodity_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(commodity_code: "0101210000", from_date: "2024-01-01", to_date: "2025-01-01")
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to include("changes")
  end

  it "returns an error for a missing from_date" do
    result = described_class.call(commodity_code: "0101210000", from_date: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("from_date")
  end

  it "returns an error when from_date is after to_date" do
    result = described_class.call(commodity_code: "0101210000", from_date: "2025-01-01", to_date: "2024-01-01")
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("from_date")
  end

  it "returns an error for an invalid commodity_code" do
    result = described_class.call(commodity_code: "short", from_date: "2024-01-01")
    expect(result.error?).to be true
  end
  # Commodity 1702609500, 1 January 2025 to 28 September 2026. Suspension 20261631 applied
  # from 27 April to 17 July 2025 only, and suspension 20265129 replaced it from 18 July.
  # The two end dates cannot show the April suspension. The start date of the July
  # suspension leads the tool to 17 July, where the April suspension is in force.
  describe "measures in force only between the two dates" do
    def measure_body(id, start_date, end_date)
      {
        "id" => id, "type" => "measure",
        "attributes" => { "effective_start_date" => "#{start_date}T00:00:00.000Z",
                          "effective_end_date" => end_date && "#{end_date}T23:59:59.000Z" },
        "relationships" => {
          "measure_type" => { "data" => { "id" => "112", "type" => "measure_type" } },
          "geographical_area" => { "data" => { "id" => "1011", "type" => "geographical_area" } }
        }
      }
    end

    def commodity_with(*measures)
      {
        "data" => {
          "id" => "1702609500", "type" => "commodity",
          "attributes" => { "goods_nomenclature_item_id" => "1702609500" },
          "relationships" => {
            "import_measures" => { "data" => measures.map { |m| { "id" => m["id"], "type" => "measure" } } },
            "export_measures" => { "data" => [] }
          }
        },
        "included" => measures + [
          { "id" => "112", "type" => "measure_type", "attributes" => { "description" => "Autonomous tariff suspension" } },
          { "id" => "1011", "type" => "geographical_area",
            "attributes" => { "geographical_area_id" => "1011", "description" => "ERGA OMNES" } }
        ]
      }.to_json
    end

    def stub_date(date, body)
      stub_request(:get, /uk\/api\/v2\/commodities\/1702609500/)
        .with(query: hash_including("as_of" => date))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
    end

    let(:april_suspension) { measure_body("20261631", "2025-04-27", "2025-07-17") }
    let(:july_suspension)  { measure_body("20265129", "2025-07-18", "2027-06-30") }

    let!(:stubs) do
      {
        "2025-01-01" => stub_date("2025-01-01", commodity_with),
        "2025-04-26" => stub_date("2025-04-26", commodity_with),
        "2025-07-17" => stub_date("2025-07-17", commodity_with(april_suspension)),
        "2025-07-18" => stub_date("2025-07-18", commodity_with(july_suspension)),
        "2026-09-28" => stub_date("2026-09-28", commodity_with(july_suspension))
      }
    end

    def run_diff
      result = described_class.call(commodity_code: "1702609500", from_date: "2025-01-01", to_date: "2026-09-28")
      JSON.parse(result.content.first[:text])
    end

    it "reports the April suspension, which neither end date shows" do
      in_between = run_diff["changes"]["measures_in_force_only_between_dates"]

      expect(in_between.length).to eq(1)
      expect(in_between.first).to include("effective_start_date" => "2025-04-27", "effective_end_date" => "2025-07-17")
    end

    it "reports the July suspension as added" do
      added = run_diff["changes"]["measures_added"]

      expect(added.map { |m| m["effective_start_date"] }).to eq([ "2025-07-18" ])
    end

    it "checks the day before each start and the day after each end inside the period" do
      expect(run_diff["dates_checked"]).to eq(%w[2025-01-01 2025-04-26 2025-07-17 2025-07-18 2026-09-28])
      stubs.each_value { |stub| expect(stub).to have_been_requested.once }
    end

    it "does not check dates outside the period" do
      stub_date("2027-07-01", commodity_with)

      run_diff

      expect(a_request(:get, /commodities\/1702609500/).with(query: hash_including("as_of" => "2027-07-01"))).not_to have_been_made
    end

    it "stops at the date limit and says so" do
      # Each measure ends on a different day, so each one adds a new date to check.
      many = (1..40).map { |day| measure_body("m#{day}", "2021-01-01", (Date.new(2025, 2, 1) + day).to_s) }
      stub_request(:get, /uk\/api\/v2\/commodities\/1702609500/)
        .to_return(status: 200, body: commodity_with(*many), headers: { "Content-Type" => "application/json" })

      parsed = run_diff

      expect(parsed["date_limit_reached"]).to be true
      expect(parsed["dates_checked"].length).to eq(described_class::MAX_DATES_CHECKED)
      expect(a_request(:get, /commodities\/1702609500/)).to have_been_made.times(described_class::MAX_DATES_CHECKED)
    end
  end
end
