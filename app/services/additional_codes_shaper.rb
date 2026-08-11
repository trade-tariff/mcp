# frozen_string_literal: true

class AdditionalCodesShaper
  def self.call(api_response)
    (api_response["data"] || []).map do |item|
      attrs = item["attributes"]
      { code: attrs["code"], type_id: attrs["additional_code_type_id"], description: attrs["description"] }.compact
    end
  end
end
