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

      it "sends the MCP user agent" do
        client = described_class.new(service: "uk")
        allow(client).to receive(:revision).and_return("abc1234")
        stub_request(:get, "#{base_url}/uk/api/v2/sections")
          .with(headers: { "User-Agent" => "TradeTariffMcp/abc1234" })
          .to_return(
            status: 200,
            body: File.read("spec/fixtures/api/sections.json"),
            headers: { "Content-Type" => "application/json" }
          )

        client.get("/uk/api/v2/sections")
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

  describe "the X-Mcp-Token header" do
    around do |example|
      original = ENV["MCP_SECRET_TOKEN"]
      example.run
      original.nil? ? ENV.delete("MCP_SECRET_TOKEN") : ENV["MCP_SECRET_TOKEN"] = original
    end

    it "is sent when MCP_SECRET_TOKEN is set" do
      ENV["MCP_SECRET_TOKEN"] = "shared-secret"
      request = stub_request(:get, "#{base_url}/uk/api/v2/sections")
        .with(headers: { "X-Mcp-Token" => "shared-secret" })
        .to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(request).to have_been_requested
    end

    it "is not sent when MCP_SECRET_TOKEN is unset" do
      ENV.delete("MCP_SECRET_TOKEN")
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(a_request(:get, "#{base_url}/uk/api/v2/sections")
        .with { |req| req.headers.key?("X-Mcp-Token") }).not_to have_been_made
    end

    it "is not sent when MCP_SECRET_TOKEN is empty" do
      ENV["MCP_SECRET_TOKEN"] = ""
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(a_request(:get, "#{base_url}/uk/api/v2/sections")
        .with { |req| req.headers.key?("X-Mcp-Token") }).not_to have_been_made
    end
  end

  describe "metrics" do
    before do
      allow(TariffApiMetrics).to receive(:record_request)
      allow(TariffApiMetrics).to receive(:record_throttled)
    end

    it "records one request per get, dimensioned by service" do
      stub_request(:get, "#{base_url}/xi/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "xi").get("/xi/api/v2/sections")

      expect(TariffApiMetrics).to have_received(:record_request).with(service: "xi").once
    end

    it "records one request per post" do
      stub_request(:post, "#{base_url}/uk/api/v2/search").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").post("/uk/api/v2/search", body: { q: "test" })

      expect(TariffApiMetrics).to have_received(:record_request).with(service: "uk").once
    end

    it "records a request even when the API errors" do
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 503, body: "{}")

      expect {
        described_class.new(service: "uk").get("/uk/api/v2/sections")
      }.to raise_error(TariffClient::ApiError)

      expect(TariffApiMetrics).to have_received(:record_request).with(service: "uk").once
    end

    it "records a throttle when the API returns 429" do
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 429, body: "{}")

      expect {
        described_class.new(service: "uk").get("/uk/api/v2/sections")
      }.to raise_error(TariffClient::RateLimited)

      expect(TariffApiMetrics).to have_received(:record_throttled).with(service: "uk").once
    end

    it "does not record a throttle on a successful response" do
      stub_request(:get, "#{base_url}/uk/api/v2/sections").to_return(status: 200, body: "{}")

      described_class.new(service: "uk").get("/uk/api/v2/sections")

      expect(TariffApiMetrics).not_to have_received(:record_throttled)
    end
  end
end
