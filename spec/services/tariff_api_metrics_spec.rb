# frozen_string_literal: true

require "rails_helper"

RSpec.describe TariffApiMetrics do
  let(:output) { StringIO.new }

  before do
    described_class.logger = Logger.new(output, formatter: ->(_severity, _time, _progname, msg) { "#{msg}\n" })
  end

  after do
    described_class.logger = nil
  end

  def emitted
    JSON.parse(output.string.lines.last)
  end

  describe ".record_request" do
    it "emits McpTariffApiRequests with a value of 1" do
      described_class.record_request(service: "uk")

      expect(emitted["McpTariffApiRequests"]).to eq(1)
    end

    it "dimensions the metric by service" do
      described_class.record_request(service: "xi")

      expect(emitted["Service"]).to eq("xi")
      expect(emitted.dig("_aws", "CloudWatchMetrics", 0, "Dimensions")).to include([ "Service" ])
    end

    it "also publishes a dimensionless series for the global rate limit alarms" do
      described_class.record_request(service: "uk")

      expect(emitted.dig("_aws", "CloudWatchMetrics", 0, "Dimensions")).to eq([ [ "Service" ], [] ])
    end

    it "emits into the TradeTariffMCP namespace" do
      described_class.record_request(service: "uk")

      expect(emitted.dig("_aws", "CloudWatchMetrics", 0, "Namespace")).to eq("TradeTariffMCP")
    end

    it "emits a millisecond timestamp" do
      described_class.record_request(service: "uk")

      expect(emitted.dig("_aws", "Timestamp")).to be_within(60_000).of((Time.now.to_f * 1000).to_i)
    end

    it "emits a single line of JSON" do
      described_class.record_request(service: "uk")

      expect(output.string.lines.length).to eq(1)
    end
  end

  describe ".record_throttled" do
    it "emits McpTariffApiThrottled with a value of 1" do
      described_class.record_throttled(service: "uk")

      expect(emitted["McpTariffApiThrottled"]).to eq(1)
      expect(emitted["McpTariffApiRequests"]).to be_nil
    end

    it "also publishes a dimensionless series for the global rate limit alarms" do
      described_class.record_throttled(service: "uk")

      expect(emitted.dig("_aws", "CloudWatchMetrics", 0, "Dimensions")).to eq([ [ "Service" ], [] ])
    end
  end

  describe "when writing fails" do
    it "does not raise" do
      broken = instance_double(Logger)
      allow(broken).to receive(:info).and_raise(IOError, "closed stream")
      described_class.logger = broken

      expect { described_class.record_request(service: "uk") }.not_to raise_error
    end
  end
end
