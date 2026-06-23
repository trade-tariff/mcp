# frozen_string_literal: true

class ClassificationSearchTool < ApplicationTool
  tool_name "classification_search"
  title "Classify a product and find commodity code candidates"
  description "First tool to call when classifying an unknown product from a natural-language product description, including commodity lookup, commodity code lookup, HS code lookup, and tariff classification requests. Searches for candidate goods nomenclatures using hybrid semantic retrieval. Use before show_heading, navigate_hierarchy, or lookup_commodity unless you already have a specific tariff code. Treat results as recall evidence, not a final classification."

  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Natural-language product description to classify or find commodity code candidates for, e.g. 'wireless bluetooth noise cancelling headphones'."
      },
      limit: {
        type: "integer",
        description: "Maximum number of candidates to return, from 1 to 50. Defaults to the backend limit.",
        minimum: 1,
        maximum: 50
      },
      expanded_query: {
        type: "string",
        description: "Optional expanded query text to use for retrieval."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "query" ]
  )

  def self.call(query:, limit: nil, expanded_query: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date) || validate_limit(limit)
    return error if error

    resolved = ServiceNormaliser.call(service)
    params = { "q" => query }
    params["limit"] = limit if limit
    params["expanded_query"] = expanded_query if expanded_query.present?

    with_error_handling do
      text_response(client_for(service: resolved).get("/#{resolved}/api/v2/classification_search", params: params, as_of: validity_date))
    end
  end

  def self.validate_limit(limit)
    return nil if limit.nil?

    value = limit.to_i
    return nil if value.between?(1, 50) && value.to_s == limit.to_s

    MCP::Tool::Response.new(
      [ { type: "text", text: "Invalid limit: '#{limit}' must be an integer from 1 to 50" } ],
      error: true
    )
  end
  private_class_method :validate_limit
end
