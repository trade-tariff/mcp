# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rspec/rails"
require "webmock/rspec"

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before do
    cw = instance_double(Aws::CloudWatch::Client, put_metric_data: nil)
    allow(Aws::CloudWatch::Client).to receive(:new).and_return(cw)
  end

  # TariffApiMetrics writes EMF JSON straight to $stdout by default, which
  # pollutes spec output every time a spec exercises TariffClient. Point it at
  # /dev/null here; specs that assert on the emitted JSON (tariff_api_metrics_spec.rb)
  # inject their own StringIO logger in a later before block, which overrides this.
  config.before do
    TariffApiMetrics.logger = Logger.new(File::NULL)
  end
end
