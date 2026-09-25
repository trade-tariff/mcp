# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rspec/rails"
require "webmock/rspec"

WebMock.disable_net_connect!

require_relative "support/cognito_token_helper"
ENV["COGNITO_USER_POOL_ID"] = CognitoTokenHelper::TEST_USER_POOL_ID
ENV["COGNITO_REGION"] = CognitoTokenHelper::TEST_REGION

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include CognitoTokenHelper
  config.include ActiveSupport::Testing::TimeHelpers

  config.before do
    Rails.cache.delete(CognitoTokenVerifier::JWKS_CACHE_KEY)

    cw = instance_double(Aws::CloudWatch::Client, put_metric_data: nil)
    allow(Aws::CloudWatch::Client).to receive(:new).and_return(cw)
  end
end
