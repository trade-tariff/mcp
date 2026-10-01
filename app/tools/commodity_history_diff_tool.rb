# frozen_string_literal: true

class CommodityHistoryDiffTool < ApplicationTool
  tool_name "commodity_history_diff"
  description "Show what changed for a specific commodity between two dates: measures added, removed or changed. Provide from_date and optionally to_date (defaults to today). Compares duty rates, supplementary units, measure conditions (both the document code a condition requires and the duty that applies when it is met) and measure footnotes. Measures are told apart by type, origin, quota order number and additional code. Also checks the dates next to each measure start and end in the period, and lists measures in force only between the two dates in measures_in_force_only_between_dates (for example, a suspension that started and ended inside the period). A very short measure between checked dates can still be missing: see coverage_note. Useful for auditing tariff changes or understanding why duty rates differ from a previous period. Each date shows the tariff as it is known today. A snapshot for any date after today, from_date or to_date, can still change, because a measure can be changed or deleted before its start date."

  # Each date is one backend request. Twenty dates keeps a long period to a few seconds.
  MAX_DATES_CHECKED = 20

  input_schema(
    properties: {
      commodity_code: {
        type: "string",
        description: "Ten-digit commodity code, e.g. '0101210000'.",
        pattern: "^\\d{10}$"
      },
      from_date: {
        type: "string",
        description: "Start date for the comparison (YYYY-MM-DD).",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      to_date: {
        type: "string",
        description: "End date for the comparison (YYYY-MM-DD). Defaults to today.",
        pattern: "^\\d{4}-\\d{2}-\\d{2}$"
      },
      service: SERVICE_SCHEMA
    },
    required: %w[commodity_code from_date]
  )

  def self.call(commodity_code:, from_date:, to_date: nil, service: nil, server_context: nil)
    to_date ||= Date.today.to_s

    error = validate_required(from_date, "from_date") ||
            validate_format(commodity_code, /\A\d{10}\z/, "commodity_code") ||
            validate_date(from_date) ||
            validate_date(to_date) ||
            validate_date_order(from_date, to_date)
    return error if error

    resolved = ServiceNormaliser.call(service)
    with_error_handling do
      params = { "include" => LookupCommodityTool::MEASURES_INCLUDE }
      client = client_for(service: resolved)
      path   = "/#{resolved}/api/v2/commodities/#{commodity_code}"

      measures_by_date = {}
      dates_to_check   = [ from_date, to_date ].uniq

      until dates_to_check.empty? || measures_by_date.length >= MAX_DATES_CHECKED
        date     = dates_to_check.shift
        raw      = client.get(path, params: params, as_of: date)
        shaped   = CommodityMeasuresShaper.call(raw, direction: "both")
        measures = (shaped[:import_measures] || []) + (shaped[:export_measures] || [])
        measures_by_date[date] = measures

        next_dates_to_check(measures, from_date, to_date).each do |next_date|
          next if measures_by_date.key?(next_date) || dates_to_check.include?(next_date)

          dates_to_check << next_date
        end
      end

      dates_between = measures_by_date.keys - [ from_date, to_date ]

      text_response(
        CommodityHistoryDiffShaper.call(
          commodity_code: commodity_code,
          from_date: from_date,
          to_date: to_date,
          from_measures: measures_by_date.fetch(from_date),
          to_measures: measures_by_date.fetch(to_date),
          measures_between_dates: dates_between.flat_map { |date| measures_by_date[date] },
          dates_checked: measures_by_date.keys.sort,
          date_limit_reached: !dates_to_check.empty?
        )
      )
    end
  end

  # A measure that starts or ends inside the period marks a date where the tariff changed.
  # The day before a start and the day after an end show the tariff on the other side of
  # that change. A measure found there can lead to more dates, which is how the tool finds
  # a measure that started and ended between from_date and to_date.
  def self.next_dates_to_check(measures, from_date, to_date)
    first_day = Date.iso8601(from_date)
    last_day  = Date.iso8601(to_date)
    dates     = []

    measures.each do |measure|
      start_day = parse_measure_date(measure[:effective_start_date])
      end_day   = parse_measure_date(measure[:effective_end_date])

      dates << (start_day - 1).iso8601 if start_day && start_day > first_day && start_day <= last_day
      dates << (end_day + 1).iso8601 if end_day && end_day >= first_day && end_day < last_day
    end

    dates.uniq
  end
  private_class_method :next_dates_to_check

  # A date the tool cannot read only means one less date to check. It must not stop the diff.
  def self.parse_measure_date(value)
    return nil if value.nil?

    Date.iso8601(value)
  rescue Date::Error
    nil
  end
  private_class_method :parse_measure_date

  def self.validate_required(value, field_name)
    return nil if value && !value.to_s.strip.empty?

    MCP::Tool::Response.new(
      [ { type: "text", text: "Missing required field: #{field_name}." } ],
      error: true
    )
  end
  private_class_method :validate_required

  def self.validate_date_order(from_date, to_date)
    return nil if from_date.nil? || to_date.nil?
    return nil if Date.parse(from_date) <= Date.parse(to_date)

    MCP::Tool::Response.new(
      [ { type: "text", text: "Invalid from_date: must be before or equal to to_date." } ],
      error: true
    )
  rescue Date::Error
    nil
  end
  private_class_method :validate_date_order
end
