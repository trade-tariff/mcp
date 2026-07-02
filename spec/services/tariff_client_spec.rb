# frozen_string_literal: true

require "rails_helper"

RSpec.describe TariffClient do
  let(:base_url) { "https://example.com" }

  before do
    @original = ENV["TARIFF_API_URL"]
    ENV["TARIFF_API_URL"] = base_url
  end

  after do
    ENV["TARIFF_API_URL"] = @original
  end

  describe "#get" do
    context "with service: uk" do
      it "calls the base URL and returns parsed JSON" do
        stub_request(:get, "#{base_url}/uk/api/v2/sections")
          .to_return(
            status: 200,
            body: File.read("spec/fixtures/api/sections.json"),
            headers: { "Content-Type" => "application/json" }
          )

        result = described_class.new(service: "uk").get("/uk/api/v2/sections")

        expect(result).to include("data")
      end
    end

    context "with service: xi" do
      it "calls the base URL with xi path" do
        stub_request(:get, "#{base_url}/xi/api/v2/sections")
          .to_return(
            status: 200,
            body: File.read("spec/fixtures/api/sections.json"),
            headers: { "Content-Type" => "application/json" }
          )

        result = described_class.new(service: "xi").get("/xi/api/v2/sections")

        expect(result).to include("data")
      end
    end

    context "when the resource is not found" do
      it "raises TariffClient::NotFound" do
        stub_request(:get, "#{base_url}/uk/api/v2/commodities/9999999999")
          .to_return(status: 404, body: "{}")

        expect {
          described_class.new(service: "uk").get("/uk/api/v2/commodities/9999999999")
        }.to raise_error(TariffClient::NotFound)
      end
    end

    context "when the API returns a server error" do
      it "raises TariffClient::ApiError" do
        stub_request(:get, "#{base_url}/uk/api/v2/sections")
          .to_return(status: 503, body: "{}")

        expect {
          described_class.new(service: "uk").get("/uk/api/v2/sections")
        }.to raise_error(TariffClient::ApiError)
      end
    end

    context "when the request times out" do
      it "raises TariffClient::ApiError" do
        stub_request(:get, "#{base_url}/uk/api/v2/sections").to_timeout

        expect {
          described_class.new(service: "uk").get("/uk/api/v2/sections")
        }.to raise_error(TariffClient::ApiError, /timed out/)
      end
    end
  end

  describe "#post" do
    context "when the request times out" do
      it "raises TariffClient::ApiError" do
        stub_request(:post, "#{base_url}/uk/api/v2/search").to_timeout

        expect {
          described_class.new(service: "uk").post("/uk/api/v2/search", body: { q: "test" })
        }.to raise_error(TariffClient::ApiError, /timed out/)
      end
    end
  end
end
