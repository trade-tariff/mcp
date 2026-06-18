# frozen_string_literal: true

class ListGeographicalAreasTool < ApplicationTool
  tool_name "list_geographical_areas"
  description "List all geographical areas (countries and country groups) recognised by the Trade Tariff. Use this to find country codes for rules of origin or duty lookups."

  input_schema(
    properties: {
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    }
  )

  def self.call(service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/geographical_areas", as_of: validity_date)
      text_response(GeographicalAreasShaper.call(raw))
    end
  end
end
