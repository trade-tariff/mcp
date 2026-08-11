# frozen_string_literal: true

require "rails_helper"

RSpec.describe InstrumentationService do
  let(:cw_client) { instance_double(Aws::CloudWatch::Client, put_metric_data: nil) }

  before do
    allow(Aws::CloudWatch::Client).to receive(:new).and_return(cw_client)
  end

  def make_response(text: "x" * 100, error: false)
    MCP::Tool::Response.new([ { type: "text", text: text } ], error: error)
  end

  describe ".record" do
    it "emits ToolCalls, ToolDuration, and ResponseBytes for a successful call" do
      described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 250, response: make_response)

      expect(cw_client).to have_received(:put_metric_data) do |args|
        names = args[:metric_data].map { |m| m[:metric_name] }
        expect(names).to include("ToolCalls", "ToolDuration", "ResponseBytes")
        expect(names).not_to include("ToolErrors", "ThinResponses")
      end
    end

    it "records ToolCalls with ToolName and ClientId dimensions" do
      described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 250, response: make_response)

      expect(cw_client).to have_received(:put_metric_data) do |args|
        calls_metric = args[:metric_data].find { |m| m[:metric_name] == "ToolCalls" }
        expect(calls_metric[:dimensions]).to contain_exactly(
          { name: "ToolName", value: "lookup_commodity" },
          { name: "ClientId", value: "client-1" }
        )
      end
    end

    it "records ResponseBytes equal to the response text bytesize" do
      described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 250, response: make_response(text: "a" * 200))

      expect(cw_client).to have_received(:put_metric_data) do |args|
        bytes_metric = args[:metric_data].find { |m| m[:metric_name] == "ResponseBytes" }
        expect(bytes_metric[:value]).to eq(200)
      end
    end

    it "emits ToolErrors with error_response type when response.error? is true" do
      described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 50, response: make_response(error: true))

      expect(cw_client).to have_received(:put_metric_data) do |args|
        error_metric = args[:metric_data].find { |m| m[:metric_name] == "ToolErrors" }
        expect(error_metric).not_to be_nil
        expect(error_metric[:dimensions]).to include({ name: "ErrorType", value: "error_response" })
      end
    end

    it "emits ThinResponses when text content is below the threshold" do
      described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 50, response: make_response(text: "x" * 10))

      expect(cw_client).to have_received(:put_metric_data) do |args|
        names = args[:metric_data].map { |m| m[:metric_name] }
        expect(names).to include("ThinResponses")
      end
    end

    it "does not emit ThinResponses when text content meets the threshold" do
      described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 50, response: make_response(text: "x" * 50))

      expect(cw_client).to have_received(:put_metric_data) do |args|
        names = args[:metric_data].map { |m| m[:metric_name] }
        expect(names).not_to include("ThinResponses")
      end
    end

    it "never raises even when the CloudWatch SDK raises" do
      allow(cw_client).to receive(:put_metric_data).and_raise(StandardError, "sdk error")

      expect {
        described_class.record(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 50, response: make_response)
      }.not_to raise_error
    end
  end

  describe ".record_exception" do
    it "emits ToolCalls, ToolDuration, and ToolErrors with exception type" do
      described_class.record_exception(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 100)

      expect(cw_client).to have_received(:put_metric_data) do |args|
        names = args[:metric_data].map { |m| m[:metric_name] }
        expect(names).to include("ToolCalls", "ToolDuration", "ToolErrors")

        error_metric = args[:metric_data].find { |m| m[:metric_name] == "ToolErrors" }
        expect(error_metric[:dimensions]).to include({ name: "ErrorType", value: "exception" })
      end
    end

    it "never raises even when the CloudWatch SDK raises" do
      allow(cw_client).to receive(:put_metric_data).and_raise(StandardError, "sdk error")

      expect {
        described_class.record_exception(tool_name: "lookup_commodity", client_id: "client-1", duration_ms: 100)
      }.not_to raise_error
    end
  end
end
