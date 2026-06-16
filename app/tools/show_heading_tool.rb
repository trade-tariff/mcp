# frozen_string_literal: true

class ShowHeadingTool < ApplicationTool
  tool_name "show_heading"
  description "Show details of a tariff heading by its 4-digit code (e.g. '0101' for live horses)."

  input_schema(
    properties: {
      heading_id: {
        type: "string",
        description: "Four-digit heading code, e.g. '0101'.",
        pattern: "\\A\\d{4}\\z"
      },
      service: {
        type: "string",
        description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
      }
    },
    required: [ "heading_id" ]
  )

  def self.call(heading_id:, service: nil, server_context: nil)
    unless heading_id.match?(/\A\d{4}\z/)
      return MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid heading_id: must be exactly 4 digits, got '#{heading_id}'" } ],
        error: true
      )
    end

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/headings/#{heading_id}")) }
  end
end
