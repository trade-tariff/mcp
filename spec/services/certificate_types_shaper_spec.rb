# frozen_string_literal: true

require "rails_helper"

RSpec.describe CertificateTypesShaper do
  def api_response(items = [])
    { "data" => items }
  end

  def cert_type(code: "C", description: "Catch certificate")
    { "id" => code, "type" => "certificate_type",
      "attributes" => { "certificate_type_code" => code, "description" => description } }
  end

  it "returns empty array when data absent" do
    expect(described_class.call({})).to eq([])
  end

  it "extracts code and description from each certificate type" do
    output = described_class.call(api_response([ cert_type ]))
    expect(output).to eq([ { code: "C", description: "Catch certificate" } ])
  end
end
