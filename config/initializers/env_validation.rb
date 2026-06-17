# frozen_string_literal: true

unless Rails.env.test?
  raise "Missing required environment variable: TARIFF_API_URL" if ENV["TARIFF_API_URL"].nil?
  raise "Missing required environment variable: TARIFF_API_TOKEN" if ENV["TARIFF_API_TOKEN"].nil?
end
