# frozen_string_literal: true

require "faraday"
require "json"

class TariffClient
  class NotFound < StandardError; end
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
    else
      raise ApiError, "API error #{response.status}: #{path}"
    end
  end

  private

  def connection
    @connection ||= Faraday.new(url: @base_url) do |f|
      f.headers["Accept"] = "application/vnd.hmrc.2.0+json"
      f.headers["Authorization"] = "Bearer #{ENV.fetch('TARIFF_API_TOKEN')}"
    end
  end
end
