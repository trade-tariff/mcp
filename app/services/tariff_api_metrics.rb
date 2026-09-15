# frozen_string_literal: true

# Emits CloudWatch metrics for outbound tariff API requests using Embedded
# Metric Format: CloudWatch extracts metrics from any log event carrying an
# "_aws" block, so this costs log ingestion rather than one PutMetricData call
# per request.
#
# It deliberately does not use Rails.logger: production wraps that in
# TaggedLogging, and the "[request-id] [client_id=...]" prefix would stop
# CloudWatch parsing the line as JSON.
class TariffApiMetrics
  NAMESPACE = ENV.fetch("MCP_METRICS_NAMESPACE", "TradeTariffMCP")
  REQUESTS_METRIC = "McpTariffApiRequests"
  THROTTLED_METRIC = "McpTariffApiThrottled"

  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new($stdout, formatter: ->(_severity, _time, _progname, msg) { "#{msg}\n" })
    end

    def record_request(service:)
      emit(REQUESTS_METRIC, service)
    end

    def record_throttled(service:)
      emit(THROTTLED_METRIC, service)
    end

    private

    def emit(metric_name, service)
      logger.info(document(metric_name, service).to_json)
      nil
    rescue StandardError
      # metrics must never surface to callers
      nil
    end

    def document(metric_name, service)
      {
        "_aws" => {
          "Timestamp" => (Time.now.to_f * 1000).to_i,
          "CloudWatchMetrics" => [
            {
              "Namespace" => NAMESPACE,
              "Dimensions" => [ [ "Service" ] ],
              "Metrics" => [ { "Name" => metric_name, "Unit" => "Count" } ]
            }
          ]
        },
        "Service" => service,
        metric_name => 1
      }
    end
  end
end
