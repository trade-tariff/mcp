# frozen_string_literal: true

class ClassificationSearchTool < ApplicationTool
  tool_name "classification_search"
  MAX_FILTER_PREFIXES = 10
  FILTER_PREFIX_FORMAT = /\A\d{2,10}\z/

  title "Find commodity code candidates"
  description "First tool to call when classifying an unknown product from a natural-language description. " \
              "Returns ranked candidate goods nomenclatures using hybrid semantic retrieval, each with a " \
              "relative_match band ('high'/'medium'/'low', or absent if no scored results exist) and its ratio to " \
              "the top result. A band compares a candidate to the best candidate for THIS query only. It is not a " \
              "calibrated probability and it is not comparable between queries — treat all results as candidates, " \
              "not a final classification, and never report a relative_match band as your confidence in a code. " \
              "Write the query as a plain description of the goods: what the product is, what it does, and what " \
              "it is made of. Do not paste a retailer product title. The search matches the words of the tariff, " \
              "and a brand name, a model name, or a word such as 'ice cream' in 'ice cream play dough' pulls the " \
              "search to the wrong heading. " \
              "Work one product at a time. Do not search every product first and then answer them together. " \
              "Each response echoes the query it answers. " \
              "Each response also groups the results by heading. The top result is often in the wrong heading: " \
              "compare several of these headings before you choose one, and do not take the heading of the top " \
              "result on trust. " \
              "One product can need two searches. Search the same product again with filter_prefixes when you have " \
              "established a heading but not the right subdivision within it: one flat shortlist often reaches the " \
              "correct heading without ever reaching the correct 10-digit code. In that second search, keep the " \
              "product description and add the fact that separates the subdivisions. Add search_non_declarables to " \
              "get headings and chapters back, so you can drill into a heading instead of choosing between leaves. " \
              "See tariff://classification-workflow for the full classification process."

  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Plain description of the goods in tariff terms: what the product is, what it does, and what it is made of, followed by legally significant product facts and unresolved pivots. Leave out brand names, model names and retailer names, and do not copy a retailer product title. For example, write 'paracetamol oral suspension medicine for children, retail pack' for 'Calpol SixPlus Suspension', 'wireless bluetooth noise cancelling headphones', or 'chocolate-flavoured whey protein powder; cocoa content not confirmed; 600g retail pack'."
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
      filter_prefixes: {
        type: "array",
        description: "Restrict the search to these goods nomenclature code prefixes, from 2 to 10 digits each. Use this for a second, narrower search once you have established the chapter or heading, e.g. ['6307'] to find the right subdivision within a heading you have already confirmed. Leave this out for the first, broad search.",
        maxItems: MAX_FILTER_PREFIXES,
        items: {
          type: "string",
          pattern: "^\\d{2,10}$"
        }
      },
      search_non_declarables: {
        type: "boolean",
        description: "Include non-declarable entries such as headings and chapters in the results. Use this when you want to find the right heading first and drill into it, rather than choose between 10-digit commodities straight away. Leave this out to use the backend default."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "query" ]
  )

  def self.call(query:, limit: nil, expanded_query: nil, filter_prefixes: nil, search_non_declarables: nil, service: nil, validity_date: nil, server_context: nil)
    prefixes = Array(filter_prefixes).map { |prefix| prefix.to_s.strip }.compact_blank.uniq
    error = validate_date(validity_date) || validate_limit(limit) || validate_filter_prefixes(prefixes)
    return error if error

    resolved = ServiceNormaliser.call(service)
    params = { "q" => query }
    params["limit"] = limit if limit
    params["expanded_query"] = expanded_query if expanded_query.present?
    params["filter_prefixes"] = prefixes.join(",") if prefixes.any?
    params["search_non_declarables"] = search_non_declarables.to_s unless search_non_declarables.nil?

    with_error_handling do
      raw = client_for(service: resolved).get("/#{resolved}/api/v2/classification_search", params: params, as_of: validity_date)
      shaped = ClassificationSearchShaper.call(raw, query: query, expanded_query: expanded_query)
      notice = if shaped[:results].empty?
        "No candidate commodity codes were found for this query. This does not mean no valid classification exists — do not guess or invent a code. Try rephrasing the query, supply expanded_query, or use full_text_search / navigate_hierarchy instead."
      end
      text_response(shaped, notice: notice)
    end
  end

  def self.validate_filter_prefixes(prefixes)
    return nil if prefixes.empty?

    if prefixes.length > MAX_FILTER_PREFIXES
      return MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid filter_prefixes: supply at most #{MAX_FILTER_PREFIXES} prefixes" } ],
        error: true
      )
    end

    invalid = prefixes.reject { |prefix| prefix.match?(FILTER_PREFIX_FORMAT) }
    return nil if invalid.empty?

    MCP::Tool::Response.new(
      [ { type: "text", text: "Invalid filter_prefixes: '#{invalid.join(', ')}' must be 2 to 10 digit codes" } ],
      error: true
    )
  end
  private_class_method :validate_filter_prefixes

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
