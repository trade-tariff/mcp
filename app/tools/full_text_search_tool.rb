# frozen_string_literal: true

# Endpoint verification (Task 6, Step 1): the backend's app/api/ directory does not exist;
# Grape/Rails routes live in app/engines/v2_api.rb. That file defines:
#   get 'search' => 'search#search'    (Api::V2::SearchController#search)
# V2Api is mounted at "/uk/api" (and "/xi/api") with version negotiated via the Accept
# header rather than a "/v2" path segment (config/routes.rb), so the real path is
# "/uk/api/search?q=...", NOT "/uk/api/v2/search" as the task brief assumed.
#
# This endpoint (backed by SearchService) does keyword/fuzzy matching against commodity,
# heading and chapter descriptions (and separately against "search references" — curated
# synonyms) using OpenSearch multi_match queries. It does NOT search chapter/section legal
# notes text — there is no separate notes search endpoint anywhere in the backend routes.
#
# Decision: implement descriptions-only keyword search (search_type: "descriptions" or
# "all", both map to the same backend call since there's only one kind of result available).
# search_type: "notes" returns a clear error — see FullTextSearchShaper::UnsupportedSearchType.
class FullTextSearchTool < ApplicationTool
  tool_name "full_text_search"
  description "Keyword search across commodity, heading and chapter descriptions using exact/fuzzy keyword matching. Complements classification_search (which is semantic/vector-based retrieval) when you need precise keyword matches rather than conceptual similarity. Note: legal notes text (chapter/section notes) cannot be searched this way — only descriptions — so search_type 'notes' is not supported."

  input_schema(
    properties: {
      query: {
        type: "string",
        description: "Keyword or phrase to search for."
      },
      search_type: {
        type: "string",
        description: "What to search: 'descriptions' or 'all' (both search commodity/heading/chapter descriptions — this is currently the only kind of keyword search the backend supports). 'notes' is not supported and returns an error.",
        enum: %w[descriptions notes all]
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "query" ]
  )

  def self.call(query:, search_type: "all", service: nil, validity_date: nil, server_context: nil)
    error = validate_query(query) ||
            validate_date(validity_date) ||
            validate_search_type(search_type)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      raw = client_for(service: resolved).get(
        "/#{resolved}/api/search",
        params: { "q" => query },
        as_of: validity_date
      )
      text_response(FullTextSearchShaper.call(raw, query: query, search_type: search_type))
    end
  end

  def self.validate_query(query)
    return nil if query && !query.strip.empty?

    MCP::Tool::Response.new(
      [ { type: "text", text: "Invalid query: must not be blank." } ],
      error: true
    )
  end
  private_class_method :validate_query

  def self.validate_search_type(search_type)
    return nil unless search_type == "notes"

    MCP::Tool::Response.new(
      [ { type: "text", text: "search_type 'notes' is not supported: the backend has no legal-notes search endpoint. Use 'descriptions' or 'all' instead." } ],
      error: true
    )
  end
  private_class_method :validate_search_type
end
