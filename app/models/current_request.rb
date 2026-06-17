# frozen_string_literal: true

class CurrentRequest < ActiveSupport::CurrentAttributes
  attribute :bearer_token
end
