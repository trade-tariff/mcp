# frozen_string_literal: true

# Runs one classification_search per item and labels every shortlist with the
# item it answers. It deliberately does NOT classify: a shortlist is retrieval
# evidence, and each item still needs the per-item workflow in
# tariff://classification-workflow. The tool exists because clients ask for
# several items at once anyway, and an unlabelled pile of shortlists in one
# context lets a code from one item attach itself to another.
class ClassifyBatchTool < ApplicationTool
  tool_name "classify_batch"
  title "Shortlist candidates for several products at once"
  description "Return a separate, labelled candidate shortlist for each of several product descriptions. " \
              "This is a retrieval helper, not a bulk classifier: it does not classify anything and it does not " \
              "return a final commodity code for any item. Each item still needs the full per-item workflow in " \
              "tariff://classification-workflow before you report a code. Use classification_search instead when " \
              "you have a single product."

  MAX_ITEMS = 10

  WORKFLOW_NOTICE = "This tool returns candidate shortlists only. It does not classify, and no code in these " \
                    "shortlists is a final answer. Work through the items one item at a time, and finish an item " \
                    "before you start the next. For every item: read the linked chapter and section notes with " \
                    "note_mentions, confirm the tariff structure with navigate_hierarchy or show_heading, apply " \
                    "the General Interpretative Rules, and ask the user for any missing product fact. Do not " \
                    "compare relative_match bands between items — each band is computed against the top result " \
                    "for its own item only, so a 'high' band for one item and a 'high' band for another item do " \
                    "not mean the same thing. Report which items you verified and which items you could not."

  input_schema(
    properties: {
      items: {
        type: "array",
        description: "The products to shortlist, from 1 to #{MAX_ITEMS} items. Each item is shortlisted independently.",
        minItems: 1,
        maxItems: MAX_ITEMS,
        items: {
          type: "object",
          properties: {
            reference: {
              type: "string",
              description: "Your own label for this item, e.g. an invoice line number. Used to tie the shortlist back to the item. Defaults to item_1, item_2, and so on."
            },
            query: {
              type: "string",
              description: "Natural-language product description, including legally significant product facts and unresolved pivots."
            },
            expanded_query: {
              type: "string",
              description: "Optional expanded query text to use for retrieval on this item only."
            }
          },
          required: [ "query" ]
        }
      },
      limit: {
        type: "integer",
        description: "Maximum candidates to return per item, from 1 to 50. Defaults to the backend limit.",
        minimum: 1,
        maximum: 50
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: [ "items" ]
  )

  def self.call(items:, limit: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_date(validity_date) || validate_limit(limit) || validate_items(items)
    return error if error

    resolved = ServiceNormaliser.call(service)
    client = client_for(service: resolved)

    shaped_items = []
    Array(items).each_with_index do |item, index|
      reference = reference_for(item, index)
      query = item_field(item, "query").to_s.strip
      expanded_query = item_field(item, "expanded_query").to_s.strip

      begin
        shaped_items << search_one(
          client: client,
          resolved: resolved,
          reference: reference,
          query: query,
          expanded_query: expanded_query,
          limit: limit,
          validity_date: validity_date
        )
      rescue TariffClient::RateLimited => e
        # Stop the whole batch. Further items would only add load to an API that
        # has already refused this one.
        return MCP::Tool::Response.new(
          [ { type: "text", text: "#{e.message}. The batch stopped at item '#{reference}' (item #{index + 1} of #{Array(items).length}). Retry with fewer items." } ],
          error: true
        )
      rescue TariffClient::NotFound, TariffClient::ApiError => e
        # Errors are values here: one bad item must not lose the other results.
        shaped_items << { reference: reference, query: query, error: "This item could not be searched: #{e.message}" }
      end
    end

    text_response({ batch_size: shaped_items.length, items: shaped_items }, notice: WORKFLOW_NOTICE)
  end

  def self.search_one(client:, resolved:, reference:, query:, expanded_query:, limit:, validity_date:)
    params = { "q" => query }
    params["limit"] = limit if limit
    params["expanded_query"] = expanded_query if expanded_query.present?

    raw = client.get("/#{resolved}/api/v2/classification_search", params: params, as_of: validity_date)
    shaped = ClassificationSearchShaper.call(raw, query: query, expanded_query: expanded_query)

    shaped[:results] = [] if shaped[:results].nil?
    shaped[:notice] = "No candidates were found for this item. Do not guess a code for it." if shaped[:results].empty?

    { reference: reference }.merge(shaped)
  end
  private_class_method :search_one

  def self.reference_for(item, index)
    reference = item_field(item, "reference").to_s.strip
    reference.presence || "item_#{index + 1}"
  end
  private_class_method :reference_for

  def self.item_field(item, key)
    return nil unless item.respond_to?(:[])

    item[key] || item[key.to_sym]
  end
  private_class_method :item_field

  def self.validate_items(items)
    list = Array(items)

    return error_response("Invalid items: supply at least 1 item") if list.empty?
    return error_response("Invalid items: supply at most #{MAX_ITEMS} items — split a longer list into several calls") if list.length > MAX_ITEMS

    list.each_with_index do |item, index|
      query = item_field(item, "query").to_s.strip
      return error_response("Invalid items: item #{index + 1} has a blank query") if query.empty?
    end

    nil
  end
  private_class_method :validate_items

  def self.validate_limit(limit)
    return nil if limit.nil?

    value = limit.to_i
    return nil if value.between?(1, 50) && value.to_s == limit.to_s

    error_response("Invalid limit: '#{limit}' must be an integer from 1 to 50")
  end
  private_class_method :validate_limit

  def self.error_response(text)
    MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
  end
  private_class_method :error_response
end
