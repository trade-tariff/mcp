# frozen_string_literal: true

require "faraday"
require "json"

class TariffClient
  class NotFound < StandardError; end
  class ApiError < StandardError; end

  BASE_URLS = {
    "uk" => -> { ENV.fetch("TARIFF_UK_API_URL") },
    "xi" => -> { ENV.fetch("TARIFF_XI_API_URL") }
  }.freeze

  def initialize(service:)
    @base_url = BASE_URLS.fetch(service).call
  end

  def get(path)
    response = connection.get(path)

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
    Faraday.new(url: @base_url) do |f|
      f.headers["Accept"] = "application/vnd.hmrc.2.0+json"
      f.headers["Content-Type"] = "application/json"
    end
  end
end
