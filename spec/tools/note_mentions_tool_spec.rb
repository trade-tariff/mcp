# frozen_string_literal: true

require "rails_helper"

RSpec.describe NoteMentionsTool do
  let(:base_url) { "https://example.com" }
  let(:response_body) do
    {
      data: [
        {
          note: {
            key: "note_fragment:customs_tariff_chapter_note:01:0001",
            source_type: "customs_tariff_chapter_note",
            source_id: "01",
            content: "This chapter covers live animals."
          },
          applies_to: [
            { goods_nomenclature_item_id: "0101210000", goods_nomenclature_sid: 123 }
          ],
          references: []
        }
      ],
      meta: {
        candidate_count: 1,
        mention_count: 1
      }
    }.to_json
  end

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "calls the UK note mentions endpoint" do
    stub = stub_request(:post, "#{base_url}/uk/api/v2/tariff_knowledge/note_mentions")
      .with(body: { goods_nomenclature_item_ids: [ "0101210000" ], goods_nomenclature_sids: [ 123 ] }.to_json)
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    result = described_class.call(goods_nomenclature_item_ids: [ "0101210000" ], goods_nomenclature_sids: [ 123 ], service: nil)

    expect(stub).to have_been_requested
    expect(JSON.parse(result.content.first[:text])).to include("data", "meta")
  end

  it "calls the XI endpoint when requested" do
    stub = stub_request(:post, "#{base_url}/xi/api/v2/tariff_knowledge/note_mentions")
      .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })

    described_class.call(goods_nomenclature_item_ids: [ "0101210000" ], service: "northern ireland")

    expect(stub).to have_been_requested
  end

  it "returns an error for invalid item ids" do
    result = described_class.call(goods_nomenclature_item_ids: [ "../../etc/passwd" ])

    expect(result).to be_error
    expect(result.content.first[:text]).to include("Invalid goods_nomenclature_item_ids")
  end

  it "returns an error for invalid SIDs" do
    result = described_class.call(goods_nomenclature_sids: [ "abc" ])

    expect(result).to be_error
    expect(result.content.first[:text]).to include("Invalid goods_nomenclature_sids")
  end
end
