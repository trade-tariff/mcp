# frozen_string_literal: true

class InstrumentationService
  NAMESPACE = ENV.fetch("MCP_METRICS_NAMESPACE", "TradeTariffMCP")
  THIN_THRESHOLD = ENV.fetch("MCP_THIN_RESPONSE_THRESHOLD", "50").to_i

  def self.record(tool_name:, client_id:, duration_ms:, response:, service: nil)
    metrics = base_metrics(tool_name, client_id, duration_ms)
    metrics << response_bytes_metric(tool_name, response)
    metrics << error_metric(tool_name, "error_response") if response.error?
    metrics << thin_response_metric(tool_name) if thin?(response)
    emit(metrics)
  end

  def self.record_exception(tool_name:, client_id:, duration_ms:)
    metrics = base_metrics(tool_name, client_id, duration_ms)
    metrics << error_metric(tool_name, "exception")
    emit(metrics)
  end

  def self.base_metrics(tool_name, client_id, duration_ms)
    [
      metric("ToolCalls", 1, "Count", [ { name: "ToolName", value: tool_name }, { name: "ClientId", value: client_id } ]),
      metric("ToolDuration", duration_ms, "Milliseconds", [ { name: "ToolName", value: tool_name } ])
    ]
  end

  def self.response_bytes_metric(tool_name, response)
    bytes = response.content.sum { |c| c[:text]&.bytesize.to_i }
    metric("ResponseBytes", bytes, "Bytes", [ { name: "ToolName", value: tool_name } ])
  end

  def self.error_metric(tool_name, error_type)
    metric("ToolErrors", 1, "Count", [ { name: "ToolName", value: tool_name }, { name: "ErrorType", value: error_type } ])
  end

  def self.thin_response_metric(tool_name)
    metric("ThinResponses", 1, "Count", [ { name: "ToolName", value: tool_name } ])
  end

  def self.thin?(response)
    bytes = response.content.sum { |c| c[:text]&.bytesize.to_i }
    bytes < THIN_THRESHOLD
  end

  def self.metric(name, value, unit, dimensions)
    { metric_name: name, value: value, unit: unit, dimensions: dimensions }
  end

  def self.emit(metrics)
    cloudwatch.put_metric_data(namespace: NAMESPACE, metric_data: metrics)
  rescue StandardError
    # never surface instrumentation failures to callers
  end

  def self.cloudwatch
    Aws::CloudWatch::Client.new(region: ENV.fetch("AWS_REGION", "eu-west-2"))
  end

  private_class_method :base_metrics, :response_bytes_metric, :error_metric,
                       :thin_response_metric, :thin?, :metric, :emit, :cloudwatch
end
