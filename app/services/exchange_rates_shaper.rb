# frozen_string_literal: true

class ExchangeRatesShaper
  def self.call(api_response)
    items = api_response["data"] || []
    by_currency = items.group_by { |item| item.dig("attributes", "currency_code") }

    by_currency.map do |currency, rates|
      most_recent = rates.max_by { |r| r.dig("attributes", "operation_date") }
      attrs = most_recent["attributes"]
      { currency: attrs["currency_code"], rate: attrs["rate"], as_of: attrs["operation_date"] }.compact
    end
  end
end
