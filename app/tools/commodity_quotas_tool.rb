# frozen_string_literal: true

class CommodityQuotasTool < ApplicationTool
  tool_name "commodity_quotas"
  description "Look up live quota balances for a commodity by its 10-digit code. Optionally filter by origin country. Returns quota order numbers, current balance, initial volume, status, and validity dates. Use this instead of search_quotas when you have a commodity code but not a quota order number."

  QUOTA_DISCOVERY_INCLUDE = "import_measures,import_measures.order_number,import_measures.geographical_area"

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "\\A\\d{10}\\z"
      },
      country_code: {
        type: "string",
        description: "ISO alpha-2 country code (e.g. 'CN', 'US'). Filters to quotas applicable to that origin."
      },
      service: SERVICE_SCHEMA,
      validity_date: VALIDITY_DATE_SCHEMA
    },
    required: ["commodity_code"]
  )

  def self.call(commodity_code:, country_code: nil, service: nil, validity_date: nil, server_context: nil)
    error = validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") ||
            validate_date(validity_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      commodity_raw = client_for(service: resolved).get(
        "/#{resolved}/api/v2/commodities/#{commodity_code}",
        params: { "include" => QUOTA_DISCOVERY_INCLUDE },
        as_of: validity_date
      )

      discovery = CommodityQuotasShaper.call(commodity_raw, country_code: country_code)
      order_numbers = discovery[:order_numbers]

      if order_numbers.empty?
        return text_response({
          commodity_code: commodity_code,
          quotas: [],
          message: "No quota measures found for this commodity#{country_code ? " and country" : ""}."
        })
      end

      quotas = order_numbers.flat_map do |order_number|
        quota_raw = client_for(service: resolved).get(
          "/#{resolved}/api/v2/quotas/search",
          params: { "order_number" => order_number },
          as_of: validity_date
        )
        SearchQuotasShaper.call(quota_raw)[:quotas]
      end

      text_response({ commodity_code: commodity_code, quotas: quotas })
    end
  end
end
