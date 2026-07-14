# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP resources" do
  before { host! "localhost" }

  def mcp_call(method, params = {})
    post "/", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
              headers: { "Content-Type" => "application/json", "Accept" => "application/json",
                         "Authorization" => "Bearer test-token" }
    JSON.parse(response.body)
  end

  describe "resources/list" do
    it "returns both resources" do
      body = mcp_call("resources/list")

      uris = body.dig("result", "resources").map { |r| r["uri"] }
      expect(uris).to contain_exactly("tariff://classification-workflow", "tariff://gri-rules")
    end

    it "returns text/markdown mime type for each resource" do
      body = mcp_call("resources/list")

      mime_types = body.dig("result", "resources").map { |r| r["mimeType"] }
      expect(mime_types).to all(eq("text/markdown"))
    end
  end

  describe "resources/read" do
    it "returns the classification workflow content" do
      body = mcp_call("resources/read", { uri: "tariff://classification-workflow" })

      contents = body.dig("result", "contents")
      expect(contents).to be_an(Array)
      expect(contents.first["mimeType"]).to eq("text/markdown")
      expect(contents.first["text"]).to include("UK Commodity Code Classifier")
    end

    it "returns the GRI rules content" do
      body = mcp_call("resources/read", { uri: "tariff://gri-rules" })

      contents = body.dig("result", "contents")
      expect(contents).to be_an(Array)
      expect(contents.first["mimeType"]).to eq("text/markdown")
      expect(contents.first["text"]).to include("General Rules of Interpretation")
    end

    it "returns an error for an unknown resource URI" do
      body = mcp_call("resources/read", { uri: "tariff://does-not-exist" })

      expect(body["error"]).to be_present
      expect(body.dig("error", "code")).to eq(-32_602)
    end
  end
end
