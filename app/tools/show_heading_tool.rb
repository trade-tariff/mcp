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
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "heading_id" ]
  )

  def self.call(heading_id:, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(heading_id, /\A\d{4}\z/, "heading_id") || validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling { text_response(client_for(service: resolved).get("/#{resolved}/api/v2/headings/#{heading_id}", as_of: validity_date)) }
  end
end
