# frozen_string_literal: true

class ApplicationTool < MCP::Tool
  class << self
    protected

    def client_for(service:)
      TariffClient.new(service: service)
    end

    def with_error_handling
      yield
    rescue TariffClient::NotFound => e
      MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
    rescue TariffClient::ApiError => e
      raise StandardError, "Backend API error: #{e.message}"
    rescue ArgumentError => e
      raise StandardError, e.message
    end

    def text_response(data)
      MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
    end
  end
end
