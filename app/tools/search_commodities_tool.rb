# frozen_string_literal: true

require "cgi"

class SearchCommoditiesTool < ApplicationTool
  tool_name "search_commodities"
  description "Search the Trade Tariff by keyword. Returns matching commodities, headings, and chapters."

  arguments do
    required(:query).filled(:string).description("Search term, e.g. 'horses' or 'bicycle parts'.")
    optional(:service).filled(:string).description("The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'.")
  end

  def call(query:, service: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { client_for(service: resolved).get("/#{resolved}/api/v2/search?q=#{CGI.escape(query)}") }
  end
end
