# frozen_string_literal: true

class NoteMentionsTool < ApplicationTool
  tool_name "note_mentions"
  description "Return chapter and section note fragments linked through the tariff knowledge graph to a shortlist of candidate goods nomenclatures."

  input_schema(
    properties: {
      goods_nomenclature_item_ids: {
        type: "array",
        description: "Candidate goods nomenclature item IDs from classification_search, navigate_hierarchy, or show_heading.",
        items: {
          type: "string",
          pattern: "\\A\\d{4,10}\\z"
        }
      },
      goods_nomenclature_sids: {
        type: "array",
        description: "Candidate goods nomenclature SIDs from classification_search.",
        items: {
          type: "integer"
        }
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    }
  )

  def self.call(goods_nomenclature_item_ids: [], goods_nomenclature_sids: [], service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date) ||
      validate_collection(goods_nomenclature_item_ids, /\A\d{4,10}\z/, "goods_nomenclature_item_ids") ||
      validate_collection(goods_nomenclature_sids, /\A\d+\z/, "goods_nomenclature_sids")
    return error if error

    resolved = ServiceNormaliser.call(service)
    body = {
      goods_nomenclature_item_ids: Array(goods_nomenclature_item_ids).compact,
      goods_nomenclature_sids: Array(goods_nomenclature_sids).compact
    }

    with_error_handling do
      text_response(client_for(service: resolved).post("/#{resolved}/api/v2/tariff_knowledge/note_mentions", body: body, as_of: validity_date))
    end
  end

  def self.validate_collection(values, pattern, field_name)
    Array(values).each do |value|
      next if value.to_s.match?(pattern)

      return MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid #{field_name}: '#{value}' does not match expected format" } ],
        error: true
      )
    end

    nil
  end
  private_class_method :validate_collection
end
