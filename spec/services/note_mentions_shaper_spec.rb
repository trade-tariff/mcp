# frozen_string_literal: true

require "rails_helper"

RSpec.describe NoteMentionsShaper do
  let(:raw) { JSON.parse(File.read("spec/fixtures/api/note_mentions.json")) }

  it "returns an array of note fragments" do
    output = described_class.call(raw)
    expect(output[:notes]).to be_an(Array)
    expect(output[:notes].length).to eq(1)
  end

  it "extracts source_type, source_id, and content from each note fragment" do
    note = described_class.call(raw)[:notes].first
    expect(note[:source_type]).to eq("customs_tariff_chapter_note")
    expect(note[:source_id]).to eq("01")
    expect(note[:content]).to eq("This chapter covers live animals.")
  end

  it "includes meta fields" do
    output = described_class.call(raw)
    expect(output[:result_count]).to eq(1)
    expect(output[:truncated]).to be false
  end

  it "returns empty notes when data is absent" do
    output = described_class.call({})
    expect(output[:notes]).to eq([])
  end

  it "filters out non-note-fragment nodes" do
    raw_with_non_note = raw.dup
    raw_with_non_note["data"] << {
      "type" => "knowledge_graph_node",
      "id" => "goods_nomenclature:123",
      "attributes" => { "node_type" => "goods_nomenclature" }
    }
    output = described_class.call(raw_with_non_note)
    expect(output[:notes].length).to eq(1)
  end
end
