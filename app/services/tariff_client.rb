# frozen_string_literal: true

require "faraday"
require "json"

class TariffClient
  class NotFound < StandardError; end
  class RateLimited < StandardError; end
  class ApiError < StandardError; end

  VALID_SERVICES = %w[uk xi].freeze

  def initialize(service:)
    raise ArgumentError, "Unknown service: #{service}" unless VALID_SERVICES.include?(service)

    @base_url = ENV.fetch("TARIFF_API_URL")
  end

  def get(path, params: {}, as_of: nil)
    response = connection.get(path) do |req|
      req.params.merge!(params)
      req.params["as_of"] = as_of if as_of
    end

    case response.status
    when 200..299
      JSON.parse(response.body)
    when 404
      raise NotFound, "Resource not found: #{path}"
    when 429
      raise RateLimited, "Rate limit exceeded — too many requests to the tariff API"
    else
      raise ApiError, "API error #{response.status}: #{path}"
    end
  end

  private

  def connection
    Faraday.new(url: @base_url) do |f|
      f.headers["Accept"] = "application/vnd.hmrc.2.0+json"
      f.headers["Authorization"] = "Bearer #{CurrentRequest.bearer_token}" if CurrentRequest.bearer_token
      f.headers["X-Mcp-Token"] = ENV["MCP_SECRET_TOKEN"] if ENV["MCP_SECRET_TOKEN"].present?
    end
  end
end
