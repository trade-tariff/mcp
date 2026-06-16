# frozen_string_literal: true

class LookupCommodityTool < ApplicationTool
  tool_name "lookup_commodity"
  description "Look up a commodity by its 10-digit commodity code. Returns description, measures, duties, and other tariff details."

  arguments do
    required(:commodity_code).filled(:string).description("Ten-digit commodity code, e.g. '0101210000'.")
    optional(:service).filled(:string).description("The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'.")
  end

  def call(commodity_code:, service: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { client_for(service: resolved).get("/#{resolved}/api/v2/commodities/#{commodity_code}") }
  end
end
