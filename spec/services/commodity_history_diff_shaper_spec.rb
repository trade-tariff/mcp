# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommodityHistoryDiffShaper do
  def measure(type:, geo:, duty: nil, quota: nil, conditions: nil, footnotes: nil, unit: nil, start_date: nil, end_date: nil, additional_code: nil)
    {
      type: type,
      geographical_area: geo,
      duty: duty,
      unit: unit,
      quota_order_number: quota,
      additional_code: additional_code,
      conditions: conditions,
      footnotes: footnotes,
      effective_start_date: start_date,
      effective_end_date: end_date
    }.compact
  end

  let(:m_third_erga_12) { measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %") }
  let(:m_third_erga_8)  { measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "8.00 %") }
  let(:m_pref_eu)       { measure(type: "Tariff preference", geo: "European Union (1013)", duty: "0.00 %") }

  def diff(from_measures, to_measures)
    described_class.call(
      commodity_code: "0101210000",
      from_date: "2024-01-01", to_date: "2025-01-01",
      from_measures: from_measures, to_measures: to_measures
    )
  end

  it "returns empty changes when both snapshots are identical" do
    result = diff([ m_third_erga_12 ], [ m_third_erga_12 ])

    expect(result[:changes][:measures_added]).to be_empty
    expect(result[:changes][:measures_removed]).to be_empty
    expect(result[:changes][:measures_changed]).to be_empty
    expect(result[:identical]).to be true
  end

  it "detects a removed measure" do
    result = diff([ m_third_erga_12, m_pref_eu ], [ m_third_erga_12 ])

    expect(result[:changes][:measures_removed].length).to eq(1)
    expect(result[:changes][:measures_removed].first[:type]).to eq("Tariff preference")
  end

  it "detects an added measure" do
    result = diff([ m_third_erga_12 ], [ m_third_erga_12, m_pref_eu ])

    expect(result[:changes][:measures_added].length).to eq(1)
    expect(result[:changes][:measures_added].first[:type]).to eq("Tariff preference")
  end

  it "detects a duty rate change" do
    result = diff([ m_third_erga_12 ], [ m_third_erga_8 ])

    expect(result[:changes][:measures_changed].length).to eq(1)
    change = result[:changes][:measures_changed].first
    expect(change[:type]).to eq("Third country duty")
    expect(change[:changed_fields][:duty]).to eq(from: "12.00 %", to: "8.00 %")
  end

  it "includes unchanged_measure_count" do
    result = diff([ m_third_erga_12, m_pref_eu ], [ m_third_erga_12 ])

    expect(result[:unchanged_measure_count]).to eq(1)
  end

  it "counts both measures unchanged when two measures share the same key with different duty rates" do
    both = [ m_third_erga_12, m_third_erga_8 ]
    result = diff(both, both)

    expect(result[:changes][:measures_added]).to be_empty
    expect(result[:changes][:measures_removed]).to be_empty
    expect(result[:changes][:measures_changed]).to be_empty
    expect(result[:unchanged_measure_count]).to eq(2)
  end

  it "matches the unaffected same-key measure as unchanged when its sibling's duty changes" do
    m_third_erga_5 = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "5.00 %")

    result = diff([ m_third_erga_12, m_third_erga_8 ], [ m_third_erga_12, m_third_erga_5 ])

    expect(result[:changes][:measures_changed].length).to eq(1)
    expect(result[:changes][:measures_changed].first[:changed_fields][:duty]).to eq(from: "8.00 %", to: "5.00 %")
    expect(result[:unchanged_measure_count]).to eq(1)
  end

  # Commodity 1702609500: measure 20261631 (suspension, no conditions) was end-dated on
  # 17 July 2025 and reissued as 20265129 with mandatory document code 9Y12 from 18 July.
  # Duty, type and origin are unchanged, so a duty-only comparison reports "identical".
  describe "a reissued measure that adds a mandatory document code" do
    let(:suspension_without_condition) do
      measure(type: "Autonomous tariff suspension", geo: "ERGA OMNES (1011)", duty: "0.00 %",
              start_date: "2025-04-27", end_date: "2025-07-17")
    end

    let(:suspension_with_9y12) do
      measure(type: "Autonomous tariff suspension", geo: "ERGA OMNES (1011)", duty: "0.00 %",
              conditions: [ { condition: "B", document_code: "9Y12", action: "Apply the mentioned duty" } ],
              start_date: "2025-07-18", end_date: "2027-06-30")
    end

    it "reports the measure as changed, not identical" do
      result = diff([ suspension_without_condition ], [ suspension_with_9y12 ])

      expect(result[:identical]).to be_nil
      expect(result[:changes][:measures_changed].length).to eq(1)
    end

    it "reports the added condition with its document code" do
      result = diff([ suspension_without_condition ], [ suspension_with_9y12 ])
      change = result[:changes][:measures_changed].first

      expect(change[:changed_fields][:conditions][:from]).to be_nil
      expect(change[:changed_fields][:conditions][:to].first[:document_code]).to eq("9Y12")
    end

    it "does not report a duty change when only the condition changed" do
      result = diff([ suspension_without_condition ], [ suspension_with_9y12 ])

      expect(result[:changes][:measures_changed].first[:changed_fields]).not_to have_key(:duty)
    end
  end

  it "detects an added footnote and reports footnotes by code" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: "CD624", description: "Health entry document required" } ])
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: "CD624", description: "Health entry document required" },
                                { code: "CD686", description: "Further controls apply" } ])

    result = diff([ from ], [ to ])

    expect(result[:changes][:measures_changed].length).to eq(1)
    expect(result[:changes][:measures_changed].first[:changed_fields][:footnotes]).to eq(
      from: %w[CD624], to: %w[CD624 CD686]
    )
  end

  # Observed on commodity 1702609500: footnote CD737 was reworded between May and August
  # 2025 with no change to what a trader must do. Wording edits must not read as changes.
  it "ignores a reworded footnote description when the footnote codes are unchanged" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: "CD737", description: "Samples are exempt." } ])
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: "CD737", description: "Samples are exempt, as retained in UK law." } ])

    result = diff([ from ], [ to ])

    expect(result[:identical]).to be true
    expect(result[:unchanged_measure_count]).to eq(1)
  end

  # A footnote arriving without a code must not stop the whole comparison. Sorting a list
  # that holds a nil raises, and the tool would then report nothing at all for the
  # commodity rather than the one measure it could not describe.
  it "does not raise when a footnote has no code" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: nil, description: "Unknown" },
                                { code: "CD624", description: "Health entry document required" } ])
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: "CD624", description: "Health entry document required" } ])

    expect { diff([ from ], [ to ]) }.not_to raise_error
  end

  it "reports a footnote that has no code as a difference rather than hiding it" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: nil, description: "Unknown" },
                                { code: "CD624", description: "Health entry document required" } ])
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   footnotes: [ { code: "CD624", description: "Health entry document required" } ])

    result = diff([ from ], [ to ])

    expect(result[:identical]).to be_nil
    expect(result[:changes][:measures_changed].first[:changed_fields]).to have_key(:footnotes)
  end

  # Conditions are compared on their own fields, not on a string of the whole hash. Two
  # conditions that hold the same values are the same condition, whatever order the keys
  # were built in.
  it "treats two conditions with the same values as unchanged" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   conditions: [ { condition: "B", document_code: "9Y12", action: "apply" } ])
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   conditions: [ { action: "apply", document_code: "9Y12", condition: "B" } ])

    result = diff([ from ], [ to ])

    expect(result[:identical]).to be true
    expect(result[:unchanged_measure_count]).to eq(1)
  end

  # Observed on commodity 2203000100. The action text is the same for every excise band
  # ("Apply the amount of the action (see components)") and the rate that applies when the
  # condition is met sits only in duty_expression. A reissue that changes that rate and
  # nothing else must not compare equal.
  it "detects a change to the duty that applies under a condition" do
    from = measure(type: "Excise", geo: "ERGA OMNES (1011)",
                   conditions: [ { condition: "V", action: "Apply the amount of the action (see components)",
                                   duty_expression: "9.96 GBP / % vol/hl" } ])
    to   = measure(type: "Excise", geo: "ERGA OMNES (1011)",
                   conditions: [ { condition: "V", action: "Apply the amount of the action (see components)",
                                   duty_expression: "10.50 GBP / % vol/hl" } ])

    result = diff([ from ], [ to ])

    expect(result[:identical]).to be_nil
    expect(result[:changes][:measures_changed].length).to eq(1)
    expect(result[:changes][:measures_changed].first[:changed_fields]).to have_key(:conditions)
  end

  # Observed on commodity 2203000100, which has seven type 306 measures for area 1400 that
  # are told apart only by additional code. Without it, a change on one can be paired with
  # another and disappear.
  it "does not match two measures that differ only by additional code" do
    from = [ measure(type: "Excise", geo: "United Kingdom (1400)", duty: "9.96 GBP", additional_code: "X411"),
             measure(type: "Excise", geo: "United Kingdom (1400)", duty: "19.08 GBP", additional_code: "X431") ]
    to   = [ measure(type: "Excise", geo: "United Kingdom (1400)", duty: "10.50 GBP", additional_code: "X411"),
             measure(type: "Excise", geo: "United Kingdom (1400)", duty: "19.08 GBP", additional_code: "X431") ]

    result = diff(from, to)

    expect(result[:unchanged_measure_count]).to eq(1)
    expect(result[:changes][:measures_changed].length).to eq(1)
    expect(result[:changes][:measures_changed].first[:additional_code]).to eq("X411")
    expect(result[:changes][:measures_changed].first[:changed_fields][:duty]).to eq(
      from: "9.96 GBP", to: "10.50 GBP"
    )
  end

  it "reports the additional code on a measure that was added or removed" do
    from = [ measure(type: "Excise", geo: "United Kingdom (1400)", duty: "9.96 GBP", additional_code: "X411") ]
    to   = [ measure(type: "Excise", geo: "United Kingdom (1400)", duty: "9.96 GBP", additional_code: "X412") ]

    result = diff(from, to)

    expect(result[:changes][:measures_removed].first[:additional_code]).to eq("X411")
    expect(result[:changes][:measures_added].first[:additional_code]).to eq("X412")
  end

  it "detects a supplementary unit change" do
    from = measure(type: "Supplementary unit", geo: "ERGA OMNES (1011)", unit: "100 p/st")
    to   = measure(type: "Supplementary unit", geo: "ERGA OMNES (1011)", unit: "1000 p/st")

    result = diff([ from ], [ to ])

    expect(result[:changes][:measures_changed].first[:changed_fields][:unit]).to eq(from: "100 p/st", to: "1000 p/st")
  end

  it "treats a reissue with identical terms as unchanged" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   start_date: "2021-01-01", end_date: "2025-07-17")
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   start_date: "2025-07-18")

    result = diff([ from ], [ to ])

    expect(result[:identical]).to be true
    expect(result[:unchanged_measure_count]).to eq(1)
  end

  # The effective dates are not compared, so a measure with the same key and the same
  # start date is still reported when its duty differs. This is not an in-place edit: the
  # backend keeps only the latest version, so both date queries would return the new terms.
  it "reports different duties with the same start date as changed" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %",
                   start_date: "2021-01-01")
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "8.00 %",
                   start_date: "2021-01-01")

    change = diff([ from ], [ to ])[:changes][:measures_changed].first

    expect(change[:changed_fields]).to eq(duty: { from: "12.00 %", to: "8.00 %" })
    expect(change[:from_effective_start_date]).to eq(change[:to_effective_start_date])
  end

  it "reports a condition change alongside a duty change on the same measure" do
    from = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "12.00 %")
    to   = measure(type: "Third country duty", geo: "ERGA OMNES (1011)", duty: "8.00 %",
                   conditions: [ { condition: "B", document_code: "9Y12" } ])

    change = diff([ from ], [ to ])[:changes][:measures_changed].first

    expect(change[:changed_fields][:duty]).to eq(from: "12.00 %", to: "8.00 %")
    expect(change[:changed_fields][:conditions][:to].first[:document_code]).to eq("9Y12")
  end
end
