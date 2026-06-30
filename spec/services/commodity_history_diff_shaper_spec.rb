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

  it "counts both measures unchanged when two measures share the same key with different duty rates" do
    duplicate_key_from = [m_third_erga_12, m_third_erga_8]
    duplicate_key_to   = [m_third_erga_12, m_third_erga_8]

    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: duplicate_key_from, to_measures: duplicate_key_to
    )

    expect(result[:changes][:measures_added]).to be_empty
    expect(result[:changes][:measures_removed]).to be_empty
    expect(result[:changes][:duty_changes]).to be_empty
    expect(result[:unchanged_measure_count]).to eq(2)
    expect(result[:identical]).to be true
  end

  it "matches the unaffected same-key measure as unchanged when its sibling's duty changes" do
    # With 2 measures sharing a key on each side, matching is by exact duty value (not
    # positional), so a duty value disappearing/appearing shows as removed+added rather
    # than a single duty_change — but the OTHER same-key measure (duty unchanged) must
    # still be correctly counted as unchanged, not swept up as a false positive.
    m_third_erga_8_changed = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "5.00 %")

    from_measures = [m_third_erga_12, m_third_erga_8]
    to_measures   = [m_third_erga_12, m_third_erga_8_changed]

    result = described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: from_measures, to_measures: to_measures
    )

    expect(result[:changes][:duty_changes]).to be_empty
    expect(result[:changes][:measures_removed].length).to eq(1)
    expect(result[:changes][:measures_removed].first[:duty]).to eq("8.00 %")
    expect(result[:changes][:measures_added].length).to eq(1)
    expect(result[:changes][:measures_added].first[:duty]).to eq("5.00 %")

    # The 12.00% measure on both sides matched by duty value and is counted unchanged.
    expect(result[:unchanged_measure_count]).to eq(1)
  end
end
