# frozen_string_literal: true

source "https://rubygems.org"

ruby "4.0.5"

gem "rails", require: false
gem "puma"
gem "mcp"
gem "faraday"
gem "redis"
gem "aws-sdk-cloudwatch"
gem "dotenv-rails", groups: %i[development test]

# Pin resolv to patch CVE-2026-80212 / CVE-2026-80213. The ruby:alpine base
# image ships resolv 0.7.0 as a bundled default gem; without this pin a bare
# `require "resolv"` anywhere in the dependency chain loads that vulnerable
# copy with no Bundler-managed override.
gem "resolv", "~> 0.8.0"

group :development, :test do
  gem "rspec-rails"
  gem "webmock"
  gem "rubocop-rails-omakase", require: false
  gem "brakeman", require: false
  gem "bundler-audit", require: false
end
