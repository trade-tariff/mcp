# frozen_string_literal: true

class ListGeographicalAreasTool < ApplicationTool
  tool_name "list_geographical_areas"
  description "Look up geographical area IDs for country groups and trade blocs (e.g. EU=1011, ASEAN, GSP countries). ISO alpha-2 codes for individual countries (CN, US, TR, etc.) are already known — only use this tool when you need the non-obvious ID for a group or bloc."

  input_schema(
    properties: {
      filter: {
        type: "string",
        description: "Partial case-insensitive match on area description (e.g. 'EU', 'ASEAN', 'GSP'). Returns all areas when omitted."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    }
  )

  def self.call(filter: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/geographical_areas", as_of: validity_date)
      shaped = GeographicalAreasShaper.call(raw)
      filtered = filter_areas(shaped, filter)
      text_response(filtered)
    end
  end

  def self.filter_areas(areas, filter)
    return areas if filter.nil? || filter.strip.empty?

    pattern = filter.strip.downcase
    areas.select { |area| area[:description]&.downcase&.include?(pattern) }
  end
  private_class_method :filter_areas
end
