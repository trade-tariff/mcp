# frozen_string_literal: true

class ShowChapterTool < ApplicationTool
  tool_name "show_chapter"
  description "Show details of a tariff chapter by its 2-digit ID (e.g. '01' for Live Animals)."

  arguments do
    required(:chapter_id).value(:string, format?: /\A\d{2}\z/).description("Two-digit chapter ID, e.g. '01'.")
    optional(:service).filled(:string).description("The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'.")
  end

  def call(chapter_id:, service: nil)
    resolved = ServiceNormaliser.call(service)
    with_error_handling { client_for(service: resolved).get("/#{resolved}/api/v2/chapters/#{chapter_id}") }
  end
end
