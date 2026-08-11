# frozen_string_literal: true

class ExchangeRatesShaper
  def self.call(api_response)
    items = api_response["data"] || []
    items.map do |item|
      attrs = item["attributes"]
      {
        currency: attrs["child_monetary_unit_code"],
        rate: attrs["exchange_rate"],
        as_of: attrs["operation_date"]
      }.compact
    end
  end
end
