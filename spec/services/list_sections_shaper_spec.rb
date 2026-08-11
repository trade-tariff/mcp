# frozen_string_literal: true

require "rails_helper"

RSpec.describe ListSectionsShaper do
  def api_response(items = [])
    { "data" => items }
  end

  def section(numeral: "I", title: "Live animals; animal products", from: "01", to: "05", position: 1)
    { "id" => "1", "type" => "section",
      "attributes" => { "numeral" => numeral, "title" => title,
                        "chapter_from" => from, "chapter_to" => to, "position" => position } }
  end

  it "returns empty array when data absent" do
    expect(described_class.call({})).to eq([])
  end

  it "extracts numeral, title and chapter range" do
    output = described_class.call(api_response([ section ]))
    expect(output).to eq([
      { numeral: "I", title: "Live animals; animal products", chapters: "01-05" }
    ])
  end

  it "uses a single chapter string when from equals to" do
    output = described_class.call(api_response([ section(from: "77", to: "77") ]))
    expect(output.first[:chapters]).to eq("77")
  end
end
