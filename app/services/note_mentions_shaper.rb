# frozen_string_literal: true

class NoteMentionsShaper
  def self.call(api_response)
    new(api_response).call
  end

  def initialize(api_response)
    @data = api_response["data"] || []
    @meta = api_response["meta"] || {}
  end

  def call
    {
      result_count: @meta["result_count"],
      truncated: @meta["truncated"],
      notes: @data.filter_map { |node| shape_node(node) }
    }.compact
  end

  private

  def shape_node(node)
    attrs = node["attributes"]
    return nil unless attrs["node_type"] == "note_fragment"

    {
      source_type: attrs["source_type"],
      source_id: attrs["source_id"],
      content: attrs["content"]
    }.compact
  end
end
