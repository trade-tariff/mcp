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

    @base_url = ENV.fetch("TARIFF_API_URL_#{service.upcase}") { ENV.fetch("TARIFF_API_URL") }
  end

  def get(path, params: {}, as_of: nil)
    response = connection.get(path) do |req|
      req.params.merge!(params)
      req.params["as_of"] = as_of if as_of
    end
    handle_response(response, path)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise ApiError, "Request timed out: #{path} (#{e.message})"
  end

  def post(path, body: {}, as_of: nil)
    response = connection.post(path) do |req|
      req.params["as_of"] = as_of if as_of
      req.headers["Content-Type"] = "application/json"
      req.body = body.to_json
    end
    handle_response(response, path)
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise ApiError, "Request timed out: #{path} (#{e.message})"
  end

  private

  def handle_response(response, path)
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

  def connection
    Faraday.new(url: @base_url, ssl: ssl_options) do |f|
      f.options.open_timeout = 5
      f.options.timeout = 30
      f.headers["Accept"] = "application/vnd.hmrc.2.0+json"
      f.headers["Authorization"] = "Bearer #{CurrentRequest.bearer_token}" if CurrentRequest.bearer_token
    end
  end

  def ssl_options
    return { verify: false } if URI.parse(@base_url).host&.end_with?(".internal")

    {}
  end
end
