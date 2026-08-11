# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExchangeRatesShaper do
  def api_response(items = [])
    { "data" => items }
  end

  def rate(currency: "EUR", date: "2026-06-01", value: 1.18)
    { "id" => "1", "type" => "monetary_exchange_rate",
      "attributes" => { "child_monetary_unit_code" => currency, "operation_date" => date, "exchange_rate" => value } }
  end

  it "returns empty array when data absent" do
    expect(described_class.call({})).to eq([])
  end

  it "returns a flat entry for each rate record" do
    eur1 = rate(currency: "EUR", date: "2025-01-01", value: 1.10)
    eur2 = rate(currency: "EUR", date: "2026-06-01", value: 1.18)
    usd  = rate(currency: "USD", date: "2026-06-01", value: 1.27)

    output = described_class.call(api_response([ eur1, eur2, usd ]))

    expect(output.length).to eq(3)
  end

  it "maps child_monetary_unit_code to :currency and exchange_rate to :rate" do
    output = described_class.call(api_response([ rate ]))

    expect(output.first[:currency]).to eq("EUR")
    expect(output.first[:rate]).to eq(1.18)
    expect(output.first[:as_of]).to eq("2026-06-01")
  end
end
