# frozen_string_literal: true

unless Rails.env.test?
  has_api_url = ENV["TARIFF_API_URL"] ||
                (ENV["TARIFF_API_URL_UK"] && ENV["TARIFF_API_URL_XI"])

  raise "Missing required environment variable: TARIFF_API_URL or both TARIFF_API_URL_UK and TARIFF_API_URL_XI" unless has_api_url
end
