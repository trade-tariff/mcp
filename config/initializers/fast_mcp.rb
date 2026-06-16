# frozen_string_literal: true

require "fast_mcp"

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
