# frozen_string_literal: true

class ApplicationTool < MCP::Tool
  VALIDITY_DATE_SCHEMA = {
    type: "string",
    description: "Return data as it appeared on this date (YYYY-MM-DD). Defaults to today.",
    pattern: "\\A\\d{4}-\\d{2}-\\d{2}\\z"
  }.freeze

  class << self
    protected

    def client_for(service:)
      TariffClient.new(service: service)
    end

    def with_error_handling
      yield
    rescue TariffClient::NotFound => e
      MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
    rescue TariffClient::ApiError => e
      raise StandardError, "Backend API error: #{e.message}"
    rescue ArgumentError => e
      raise StandardError, e.message
    end

    def text_response(data)
      MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
    end

    def validate_date(validity_date)
      return nil if validity_date.nil? || validity_date.strip.empty?

      unless validity_date.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        return MCP::Tool::Response.new(
          [ { type: "text", text: "Invalid validity_date: must be YYYY-MM-DD, got '#{validity_date}'" } ],
          error: true
        )
      end

      nil
    end
  end
end
