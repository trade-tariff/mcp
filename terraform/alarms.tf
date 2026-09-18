# MCP traffic shares one 3,000rpm API Gateway usage plan rather than consuming
# each end user's per-key limit (HMRC-2699). Nothing else watches that ceiling,
# so these alarms are how we find out it needs reviewing.
#
# Both alarms below deliberately omit a `dimensions` block so they watch the
# metric globally, summed across services. CloudWatch does not aggregate
# across an omitted dimension on its own -- it only watches the exact
# zero-dimension series. That series exists only because
# app/services/tariff_api_metrics.rb explicitly publishes a `[]` dimension
# set alongside `["Service"]`. If that empty set is ever removed, these
# alarms silently stop watching anything (treat_missing_data = "notBreaching"
# keeps them in OK/INSUFFICIENT_DATA forever).
locals {
  mcp_rate_limit_alarm_threshold = var.mcp_rate_limit_rpm * var.mcp_rate_limit_alarm_percentage / 100
}

resource "aws_cloudwatch_metric_alarm" "approaching_rate_limit" {
  count = var.enable_mcp_rate_limit_alarms ? 1 : 0

  alarm_name          = "mcp-tariff-api-approaching-rate-limit-${var.environment}"
  alarm_description   = "MCP tariff API requests have exceeded ${var.mcp_rate_limit_alarm_percentage}% of the shared ${var.mcp_rate_limit_rpm}rpm MCP usage plan for ${var.mcp_rate_limit_alarm_periods} consecutive minutes. Review the limit in the terraform repo (environments/${var.environment}/common/gateway.tf, var.mcp_rate_limit)."
  namespace           = "TradeTariffMCP"
  metric_name         = "McpTariffApiRequests"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = var.mcp_rate_limit_alarm_periods
  datapoints_to_alarm = var.mcp_rate_limit_alarm_periods
  threshold           = local.mcp_rate_limit_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [data.aws_sns_topic.slack_topic.arn]
  ok_actions    = [data.aws_sns_topic.slack_topic.arn]
}

resource "aws_cloudwatch_metric_alarm" "rate_limited" {
  count = var.enable_mcp_rate_limit_alarms ? 1 : 0

  alarm_name          = "mcp-tariff-api-rate-limited-${var.environment}"
  alarm_description   = "The tariff API returned 429 to the MCP server. Most likely the shared ${var.mcp_rate_limit_rpm}rpm MCP usage plan is exhausted, but WAF, a per-user plan, or the backend can also produce this. Check the access logs to confirm which."
  namespace           = "TradeTariffMCP"
  metric_name         = "McpTariffApiThrottled"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [data.aws_sns_topic.slack_topic.arn]
  ok_actions    = [data.aws_sns_topic.slack_topic.arn]
}
