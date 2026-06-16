# frozen_string_literal: true

class NavigateHierarchyTool < ApplicationTool
  tool_name "navigate_hierarchy"
  description "Look up a goods nomenclature entry by a 4-10 digit code. Returns the item and its position in the tariff hierarchy."

  arguments do
    required(:code).filled(:string).description("4 to 10-digit goods nomenclature code, e.g. '0101' or '0101210000'.")
    optional(:service).filled(:string).description("The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'.")
  end

  def call(code:, service: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { client_for(service: resolved).get("/#{resolved}/api/v2/goods_nomenclatures/#{code}") }
  end
end
