# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationShaper do
  let(:concrete_shaper) do
    Class.new(ApplicationShaper) do
      def initialize(api_response)
        @included = build_index(api_response["included"] || [])
      end

      def call
        geo = lookup("geographical_area", "1011")
        format_geo(geo)
      end
    end
  end

  let(:api_response) do
    {
      "included" => [
        {
          "id" => "1011",
          "type" => "geographical_area",
          "attributes" => { "geographical_area_id" => "1011", "description" => "ERGA OMNES" }
        }
      ]
    }
  end

  it "builds a [type, id] index and looks items up" do
    result = concrete_shaper.call(api_response)
    expect(result).to eq("ERGA OMNES (1011)")
  end

  it "returns nil for unknown lookups" do
    shaper = concrete_shaper.new({ "included" => [] })
    expect(shaper.send(:lookup, "geographical_area", "9999")).to be_nil
  end
end
