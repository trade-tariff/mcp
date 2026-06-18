# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowHeadingTool do
  let(:base_url) { "https://example.com" }
  let(:heading_response) { File.read("spec/fixtures/api/heading.json") }

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "returns heading details for the UK service by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/headings/0101")
      .to_return(status: 200, body: heading_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(heading_id: "0101", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("heading_code")
  end

  it "calls the XI endpoint when service is NI" do
    stub_request(:get, "#{base_url}/xi/api/v2/headings/0101")
      .to_return(status: 200, body: heading_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(heading_id: "0101", service: "NI")

    expect(JSON.parse(result.content.first[:text])).to include("heading_code")
  end

  it "returns an error response when heading is not found" do
    stub_request(:get, "#{base_url}/uk/api/v2/headings/9999")
      .to_return(status: 404, body: "{}")

    result = described_class.call(heading_id: "9999", service: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns an error response for a non-numeric heading_id" do
    result = described_class.call(heading_id: "../../etc/passwd", service: nil)

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid heading_id")
  end
end
