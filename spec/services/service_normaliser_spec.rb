# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceNormaliser do
  describe ".call" do
    it "returns uk for nil" do
      expect(described_class.call(nil)).to eq("uk")
    end

    it "returns uk for empty string" do
      expect(described_class.call("")).to eq("uk")
    end

    it "returns uk for the string uk" do
      expect(described_class.call("uk")).to eq("uk")
    end

    it "returns uk for UK uppercase" do
      expect(described_class.call("UK")).to eq("uk")
    end

    it "returns uk for gb" do
      expect(described_class.call("gb")).to eq("uk")
    end

    it "returns uk for great britain" do
      expect(described_class.call("great britain")).to eq("uk")
    end

    it "returns uk for united kingdom" do
      expect(described_class.call("united kingdom")).to eq("uk")
    end

    it "returns xi for xi" do
      expect(described_class.call("xi")).to eq("xi")
    end

    it "returns xi for XI uppercase" do
      expect(described_class.call("XI")).to eq("xi")
    end

    it "returns xi for ni" do
      expect(described_class.call("ni")).to eq("xi")
    end

    it "returns xi for NI uppercase" do
      expect(described_class.call("NI")).to eq("xi")
    end

    it "returns xi for northern ireland" do
      expect(described_class.call("northern ireland")).to eq("xi")
    end

    it "returns xi for Northern Ireland mixed case" do
      expect(described_class.call("Northern Ireland")).to eq("xi")
    end

    it "returns xi for northern_ireland with underscore" do
      expect(described_class.call("northern_ireland")).to eq("xi")
    end

    it "returns xi for NORTHERN IRELAND all caps" do
      expect(described_class.call("NORTHERN IRELAND")).to eq("xi")
    end

    it "raises ArgumentError for unrecognised non-empty input" do
      expect { described_class.call("germany") }.to raise_error(ArgumentError, /Unknown service/)
    end

    it "raises ArgumentError for whitespace-only input that resolves to an unknown value" do
      # whitespace-only is treated as blank → uk (no error)
      expect(described_class.call("   ")).to eq("uk")
    end
  end
end
