# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowHeadingTool do
  let(:uk_base_url) { "https://uk.example.com" }
  let(:xi_base_url) { "https://xi.example.com" }
  let(:heading_response) { File.read("spec/fixtures/api/heading.json") }

  before do
    ENV["TARIFF_UK_API_URL"] = uk_base_url
    ENV["TARIFF_XI_API_URL"] = xi_base_url
  end

  after do
    ENV.delete("TARIFF_UK_API_URL")
    ENV.delete("TARIFF_XI_API_URL")
  end

  it "returns heading details for the UK service by default" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/headings/0101")
      .to_return(status: 200, body: heading_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(heading_id: "0101", service: nil)

    expect(result).to include("data")
  end

  it "calls the XI endpoint when service is NI" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/headings/0101")
      .to_return(status: 200, body: heading_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(heading_id: "0101", service: "NI")

    expect(result).to include("data")
  end

  it "raises StandardError when heading is not found" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/headings/9999")
      .to_return(status: 404, body: "{}")

    expect {
      described_class.new.call(heading_id: "9999", service: nil)
    }.to raise_error(StandardError, /Not found/)
  end

  it "raises FastMcp::Tool::InvalidArgumentsError for a non-numeric heading_id" do
    expect {
      described_class.new.call_with_schema_validation!(heading_id: "../../etc/passwd", service: nil)
    }.to raise_error(FastMcp::Tool::InvalidArgumentsError)
  end
end
