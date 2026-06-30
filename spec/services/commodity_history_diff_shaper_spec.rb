# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityHistoryDiffShaper do
  def measure(type:, geo:, duty:, quota: nil)
    { type: type, geographical_area: geo, duty: duty, quota_order_number: quota }
  end

  let(:m_third_erga_12) { measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %") }
  let(:m_third_erga_8)  { measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "8.00 %") }
  let(:m_pref_eu)       { measure(type: "Tariff preference", geo: "European Union (1013)", duty: "0.00 %") }

  it "returns empty changes when both snapshots are identical" do
    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: [m_third_erga_12], to_measures: [m_third_erga_12]
    )
    expect(result[:changes][:measures_added]).to be_empty
    expect(result[:changes][:measures_removed]).to be_empty
    expect(result[:changes][:duty_changes]).to be_empty
    expect(result[:identical]).to be true
  end

  it "detects a removed measure" do
    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: [m_third_erga_12, m_pref_eu], to_measures: [m_third_erga_12]
    )
    expect(result[:changes][:measures_removed].length).to eq(1)
    expect(result[:changes][:measures_removed].first[:type]).to eq("Tariff preference")
  end

  it "detects an added measure" do
    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: [m_third_erga_12], to_measures: [m_third_erga_12, m_pref_eu]
    )
    expect(result[:changes][:measures_added].length).to eq(1)
    expect(result[:changes][:measures_added].first[:type]).to eq("Tariff preference")
  end

  it "detects a duty rate change" do
    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: [m_third_erga_12], to_measures: [m_third_erga_8]
    )
    expect(result[:changes][:duty_changes].length).to eq(1)
    change = result[:changes][:duty_changes].first
    expect(change[:from]).to eq("12.00 %")
    expect(change[:to]).to eq("8.00 %")
  end

  it "includes unchanged_measure_count" do
    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: [m_third_erga_12, m_pref_eu], to_measures: [m_third_erga_12]
    )
    expect(result[:unchanged_measure_count]).to eq(1)
  end
end
