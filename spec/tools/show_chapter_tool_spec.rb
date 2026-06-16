# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowChapterTool do
  let(:uk_base_url) { "https://uk.example.com" }
  let(:xi_base_url) { "https://xi.example.com" }
  let(:chapter_response) { File.read("spec/fixtures/api/chapter.json") }

  before do
    ENV["TARIFF_UK_API_URL"] = uk_base_url
    ENV["TARIFF_XI_API_URL"] = xi_base_url
  end

  after do
    ENV.delete("TARIFF_UK_API_URL")
    ENV.delete("TARIFF_XI_API_URL")
  end

  it "returns chapter details for the UK service by default" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/chapters/01")
      .to_return(status: 200, body: chapter_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(chapter_id: "01", service: nil)

    expect(result).to include("data")
  end

  it "calls the XI endpoint when service is northern ireland" do
    stub_request(:get, "#{xi_base_url}/xi/api/v2/chapters/01")
      .to_return(status: 200, body: chapter_response, headers: { "Content-Type" => "application/json" })

    result = described_class.new.call(chapter_id: "01", service: "northern ireland")

    expect(result).to include("data")
  end

  it "raises StandardError when chapter is not found" do
    stub_request(:get, "#{uk_base_url}/uk/api/v2/chapters/99")
      .to_return(status: 404, body: "{}")

    expect {
      described_class.new.call(chapter_id: "99", service: nil)
    }.to raise_error(StandardError, /Not found/)
  end
end
