# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExchangeRatesShaper do
  def api_response(items = [])
    { "data" => items }
  end

  def rate(currency: "EUR", date: "2026-06-01", value: 1.18)
    { "id" => "1", "type" => "monetary_exchange_rate",
      "attributes" => { "currency_code" => currency, "operation_date" => date, "rate" => value } }
  end

  it "returns empty array when data absent" do
    expect(described_class.call({})).to eq([])
  end

  it "returns one rate per currency — the most recent by operation_date" do
    old_eur = rate(currency: "EUR", date: "2025-01-01", value: 1.10)
    new_eur = rate(currency: "EUR", date: "2026-06-01", value: 1.18)
    usd     = rate(currency: "USD", date: "2026-06-01", value: 1.27)

    output = described_class.call(api_response([ old_eur, new_eur, usd ]))

    expect(output.length).to eq(2)
    eur_rate = output.find { |r| r[:currency] == "EUR" }
    expect(eur_rate[:rate]).to eq(1.18)
    expect(eur_rate[:as_of]).to eq("2026-06-01")
  end
end
