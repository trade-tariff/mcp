# frozen_string_literal: true

# Reduces the geographical areas list response (~380KB, 366 items) to a flat
# array of {id, description} pairs (~15KB). The full response includes hjid
# and self-referential includes that are not useful to an LLM.
class GeographicalAreasShaper
  def self.call(api_response)
    (api_response["data"] || []).map do |item|
      attrs = item["attributes"]
      {
        id: attrs["geographical_area_id"] || attrs["id"],
        description: attrs["description"]
      }
    end
  end
end
