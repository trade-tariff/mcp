# frozen_string_literal: true

class ApplicationTool < MCP::Tool
  annotations(
    read_only_hint: true,
    destructive_hint: false,
    idempotent_hint: true,
    open_world_hint: true
  )

  SERVICE_SCHEMA = {
    type: "string",
    description: "The tariff service to query. Accepts 'uk' (default), 'xi', 'ni', or 'northern ireland'."
  }.freeze

  VALIDITY_DATE_SCHEMA = {
    type: "string",
    description: "Return data as it appeared on this date (YYYY-MM-DD). Defaults to today.",
    pattern: "^\\d{4}-\\d{2}-\\d{2}$"
  }.freeze

  class << self
    protected

    def client_for(service:)
      TariffClient.new(service: service)
    end

    def with_error_handling
      yield
    rescue TariffClient::NotFound => e
      MCP::Tool::Response.new([ { type: "text", text: "#{e.message}. Use show_heading or navigate_hierarchy to find valid commodity codes — do not guess or construct them." } ], error: true)
    rescue TariffClient::RateLimited => e
      MCP::Tool::Response.new([ { type: "text", text: e.message } ], error: true)
    rescue TariffClient::ApiError => e
      raise StandardError, "Backend API error: #{e.message}"
    rescue ArgumentError => e
      raise StandardError, e.message
    end

    def text_response(data)
      MCP::Tool::Response.new([ { type: "text", text: data.to_json } ])
    end

    def validate_format(value, pattern, field_name)
      return nil if value.match?(pattern)

      MCP::Tool::Response.new(
        [ { type: "text", text: "Invalid #{field_name}: '#{value}' does not match expected format" } ],
        error: true
      )
    end

    def validate_date(validity_date)
      return nil if validity_date.nil? || validity_date.strip.empty?

      validate_format(validity_date, /\A\d{4}-\d{2}-\d{2}\z/, "validity_date")
    end
  end
end
