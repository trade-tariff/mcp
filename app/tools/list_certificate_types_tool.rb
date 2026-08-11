# frozen_string_literal: true

class ListCertificateTypesTool < ApplicationTool
  tool_name "list_certificate_types"
  description "List all certificate types with their descriptions. Use this to understand what licences or certificates a commodity measure may require."

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
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/certificate_types", as_of: validity_date)
      text_response(CertificateTypesShaper.call(raw))
    end
  end
end
