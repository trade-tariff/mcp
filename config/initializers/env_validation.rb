# frozen_string_literal: true

unless Rails.env.test?
  has_api_url = ENV["TARIFF_API_URL"] ||
                (ENV["TARIFF_API_URL_UK"] && ENV["TARIFF_API_URL_XI"])

  raise "Missing required environment variable: TARIFF_API_URL or both TARIFF_API_URL_UK and TARIFF_API_URL_XI" unless has_api_url
end

# Bearer tokens are verified against this Cognito pool. Local development
# skips verification, so it does not need the pool.
unless Rails.env.test? || Rails.env.development?
  raise "Missing required environment variable: COGNITO_USER_POOL_ID" if ENV["COGNITO_USER_POOL_ID"].blank?

  # OAuth refresh tokens are encrypted with a key derived from this. Without
  # it, each task picks a random key, so a refresh token fails on the other
  # tasks and after each deploy.
  raise "Missing required environment variable: SECRET_KEY_BASE" if ENV["SECRET_KEY_BASE"].blank?
end
