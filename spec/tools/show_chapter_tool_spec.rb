# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowChapterTool do
  let(:base_url) { "https://example.com" }
  let(:chapter_response) { File.read("spec/fixtures/api/chapter.json") }

  before do
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV.delete("TARIFF_API_URL")
  end

  it "returns chapter details for the UK service by default" do
    stub_request(:get, "#{base_url}/uk/api/v2/chapters/01")
      .to_return(status: 200, body: chapter_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(chapter_id: "01", service: nil)

    expect(result).to be_a(MCP::Tool::Response)
    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "calls the XI endpoint when service is northern ireland" do
    stub_request(:get, "#{base_url}/xi/api/v2/chapters/01")
      .to_return(status: 200, body: chapter_response, headers: { "Content-Type" => "application/json" })

    result = described_class.call(chapter_id: "01", service: "northern ireland")

    expect(JSON.parse(result.content.first[:text])).to include("data")
  end

  it "returns an error response when chapter is not found" do
    stub_request(:get, "#{base_url}/uk/api/v2/chapters/99")
      .to_return(status: 404, body: "{}")

    result = described_class.call(chapter_id: "99", service: nil)
    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("not found")
  end

  it "returns an error response for a non-numeric chapter_id" do
    result = described_class.call(chapter_id: "../../etc/passwd", service: nil)

    expect(result.error?).to be true
    expect(result.content.first[:text]).to include("Invalid chapter_id")
  end
end
