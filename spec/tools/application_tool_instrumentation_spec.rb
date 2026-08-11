# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ApplicationTool instrumentation auto-wrap" do
  let(:successful_tool) do
    Class.new(ApplicationTool) do
      tool_name "instrumented_tool"

      def self.call(server_context: nil)
        MCP::Tool::Response.new([ { type: "text", text: "result data" } ])
      end
    end
  end

  let(:error_tool) do
    Class.new(ApplicationTool) do
      tool_name "error_tool"

      def self.call(server_context: nil)
        raise StandardError, "backend exploded"
      end
    end
  end

  before do
    allow(InstrumentationService).to receive(:record)
    allow(InstrumentationService).to receive(:record_exception)
  end

  it "calls InstrumentationService.record after a successful tool call" do
    successful_tool.call

    expect(InstrumentationService).to have_received(:record).with(
      tool_name: "instrumented_tool",
      client_id: anything,
      duration_ms: (be >= 0),
      response: an_instance_of(MCP::Tool::Response)
    )
  end

  it "returns the tool's response unchanged" do
    response = successful_tool.call
    expect(response).to be_a(MCP::Tool::Response)
    expect(response.content.first[:text]).to eq("result data")
  end

  it "calls InstrumentationService.record_exception and re-raises when the tool raises" do
    expect { error_tool.call }.to raise_error(StandardError, "backend exploded")

    expect(InstrumentationService).to have_received(:record_exception).with(
      tool_name: "error_tool",
      client_id: anything,
      duration_ms: (be >= 0)
    )
  end
end
