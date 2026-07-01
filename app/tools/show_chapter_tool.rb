# frozen_string_literal: true

class ShowChapterTool < ApplicationTool
  tool_name "show_chapter"
  description "Show details of a tariff chapter by its 2-digit ID (e.g. '01' for Live Animals)."

  input_schema(
    properties: {
      chapter_id: {
        type: "string",
        description: "Two-digit chapter ID, e.g. '01'.",
        pattern: "^\\d{2}$"
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "chapter_id" ]
  )

  def self.call(chapter_id:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(chapter_id, /\A\d{2}\z/, "chapter_id") || validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/chapters/#{chapter_id}", as_of: validity_date)) }
  end
end
