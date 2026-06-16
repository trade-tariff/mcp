# frozen_string_literal: true

require "fast_mcp"

unless Rails.env.test?
  %w[TARIFF_UK_API_URL TARIFF_XI_API_URL].each do |var|
    raise "Missing required environment variable: #{var}" if ENV[var].nil?
  end
end

FastMcp.mount_in_rails(
  Rails.application,
  name: "trade-tariff",
  version: "0.1.0",
  path_prefix: "/mcp"
) do |server|
  Rails.application.config.after_initialize do
    server.register_tools(*ApplicationTool.descendants)
  end
end
