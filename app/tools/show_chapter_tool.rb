# frozen_string_literal: true

class ShowChapterTool < ApplicationTool
  tool_name "show_chapter"
  description "Show details of a tariff chapter by its 2-digit ID (e.g. '01' for Live Animals)."

  input_schema(
    properties: {
      chapter_id: {
        type: "string",
        description: "Two-digit chapter ID, e.g. '01'.",
        pattern: "\\A\\d{2}\\z"
      },
      service: {
        type: "string",
        description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
      }
    },
    required: [ "chapter_id" ]
  )

  def self.call(chapter_id:, service: nil, server_context: nil)
    unless chapter_id.match?(/\A\d{2}\z/)
      return MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid chapter_id: must be exactly 2 digits, got '#{chapter_id}'" } ],
        error: true
      )
    end

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/chapters/#{chapter_id}")) }
  end
end
