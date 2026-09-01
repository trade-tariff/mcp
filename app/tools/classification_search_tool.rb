# frozen_string_literal: true

class ClassificationSearchTool < ApplicationTool
  tool_name "classification_search"
  title "Find commodity code candidates"
  description "First tool to call when classifying an unknown product from a natural-language description. Returns ranked candidate goods nomenclatures using hybrid semantic retrieval, each with a relative confidence band ('high'/'medium'/'low', or absent if no scored results exist). Confidence is relative to the top result in this search only, not a calibrated probability — treat all results as candidates, not a final classification, and never state or imply a confidence this tool did not return. See tariff://classification-workflow for the full classification process."

  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Natural-language product description to classify or find commodity code candidates for, including legally significant product facts and unresolved pivots, e.g. 'wireless bluetooth noise cancelling headphones' or 'chocolate-flavoured whey protein powder; cocoa content not confirmed; 600g retail pack'."
      },
      limit: {
        type: "integer",
        description: "Maximum number of candidates to return, from 1 to 50. Defaults to the backend limit.",
        minimum: 1,
        maximum: 50
      },
      expanded_query: {
        type: "string",
        description: "Optional expanded query text to use for retrieval. Use this to test alternate routes suggested by product pivots, e.g. 'food preparation containing cocoa protein powder retail pack under 1kg'."
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
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/classification_search", params: params, as_of: validity_date)
      shaped = ClassificationSearchShaper.call(raw)
      notice = if shaped[:results].empty?
        "No candidate commodity codes were found for this query. This does not mean no valid classification exists — do not guess or invent a code. Try rephrasing the query, supply expanded_query, or use full_text_search / navigate_hierarchy instead."
      end
      text_response(shaped, notice: notice)
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
