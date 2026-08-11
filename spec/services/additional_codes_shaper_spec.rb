# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdditionalCodesShaper do
  def api_response(items = [])
    { "data" => items }
  end

  def additional_code(code: "100", type_id: "8", description: "Sugar content 45% or more")
    { "id" => "1", "type" => "additional_code",
      "attributes" => { "code" => code, "additional_code_type_id" => type_id, "description" => description } }
  end

  it "returns empty array when data absent" do
    expect(described_class.call({})).to eq([])
  end

  it "extracts code, type_id, and description" do
    output = described_class.call(api_response([ additional_code ]))
    expect(output).to eq([ { code: "100", type_id: "8", description: "Sugar content 45% or more" } ])
  end
end
