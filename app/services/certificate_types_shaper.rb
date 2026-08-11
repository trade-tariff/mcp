# frozen_string_literal: true

class CertificateTypesShaper
  def self.call(api_response)
    (api_response["data"] || []).map do |item|
      attrs = item["attributes"]
      { code: attrs["certificate_type_code"], description: attrs["description"] }.compact
    end
  end
end
