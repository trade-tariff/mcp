# frozen_string_literal: true

class ListSectionsTool < ApplicationTool
  tool_name "list_sections"
  description "List all sections of the UK Trade Tariff. Sections are the top-level groupings of goods."

  arguments do
    optional(:service).filled(:string).description("The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'.")
  end

  def call(service: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { client_for(service: resolved).get("/#{resolved}/api/v2/sections") }
  end
end
