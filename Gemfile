# frozen_string_literal: true

source "https://rubygems.org"

ruby "4.0.5"

gem "rails", require: false
gem "fast-mcp"
gem "faraday"
gem "dotenv-rails", groups: %i[development test]

group :development, :test do
  gem "rspec-rails"
  gem "webmock"
  gem "rubocop-rails-omakase", require: false
  gem "brakeman", require: false
  gem "bundler-audit", require: false
end
