# frozen_string_literal: true

class ShowHeadingTool < ApplicationTool
  tool_name "show_heading"
  description "Show details of a tariff heading by its 4-digit code (e.g. '0101' for live horses)."

  arguments do
    required(:heading_id).filled(:string).description("Four-digit heading code, e.g. '0101'.")
    optional(:service).filled(:string).description("The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'.")
  end

  def call(heading_id:, service: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { client_for(service: resolved).get("/#{resolved}/api/v2/headings/#{heading_id}") }
  end
end
