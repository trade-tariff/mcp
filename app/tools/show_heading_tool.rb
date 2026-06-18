# frozen_string_literal: true

class ShowHeadingTool < ApplicationTool
  tool_name "show_heading"
  description "Show details of a tariff heading by its 4-digit code (e.g. '0101' for live horses). Returns the heading's commodity children with their codes — use these codes with lookup_commodity."

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
    with_error_handling do
      params = {
        "include" => "section,chapter,footnotes,commodities",
        "fields[heading]" => "goods_nomenclature_item_id,description_plain,declarable,validity_start_date,validity_end_date,section,chapter,footnotes,commodities",
        "fields[section]" => "title",
        "fields[chapter]" => "description_plain,formatted_description",
        "fields[commodity]" => "goods_nomenclature_item_id,description_plain,declarable,leaf",
        "fields[footnote]" => "code,description"
      }
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/headings/#{heading_id}", params: params, as_of: validity_date)
      text_response(HeadingShaper.call(raw))
    end
  end
end
