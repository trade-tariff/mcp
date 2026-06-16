# frozen_string_literal: true

unless Rails.env.test?
  %w[TARIFF_UK_API_URL TARIFF_XI_API_URL].each do |var|
    raise "Missing required environment variable: #{var}" if ENV[var].nil?
  end
end
