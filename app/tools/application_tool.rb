# frozen_string_literal: true

class ApplicationTool < FastMcp::Tool
  protected

  def client_for(service:)
    resolved = ServiceNormaliser.call(service)
    TariffClient.new(service: resolved)
  end

  def with_error_handling
    yield
  rescue TariffClient::NotFound => e
    raise StandardError, "Not found: #{e.message}"
  rescue TariffClient::ApiError => e
    raise StandardError, "Backend API error: #{e.message}"
  end
end
