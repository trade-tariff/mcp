# frozen_string_literal: true

class CommodityHistoryDiffShaper
  def self.call(commodity_code:, from_date:, to_date:, from_measures:, to_measures:)
    new(commodity_code: commodity_code, from_date: from_date, to_date: to_date,
        from_measures: from_measures, to_measures: to_measures).call
  end

  def initialize(commodity_code:, from_date:, to_date:, from_measures:, to_measures:)
    @commodity_code = commodity_code
    @from_date      = from_date
    @to_date        = to_date
    @from_measures  = from_measures
    @to_measures    = to_measures
  end

  def call
    from_index = index_by_key(@from_measures)
    to_index   = index_by_key(@to_measures)

    from_keys = from_index.keys.to_set
    to_keys   = to_index.keys.to_set

    added   = (to_keys - from_keys).map { |k| to_index[k] }
    removed = (from_keys - to_keys).map { |k| from_index[k] }

    duty_changes = (from_keys & to_keys).filter_map do |k|
      from_m = from_index[k]
      to_m   = to_index[k]
      next if from_m[:duty] == to_m[:duty]

      {
        type: from_m[:type],
        geographical_area: from_m[:geographical_area],
        quota_order_number: from_m[:quota_order_number],
        from: from_m[:duty],
        to: to_m[:duty]
      }.compact
    end

    unchanged_count = (from_keys & to_keys).count { |k| from_index[k][:duty] == to_index[k][:duty] }
    identical = added.empty? && removed.empty? && duty_changes.empty?

    result = {
      commodity_code: @commodity_code,
      from_date: @from_date,
      to_date: @to_date,
      changes: {
        measures_added: added,
        measures_removed: removed,
        duty_changes: duty_changes
      },
      unchanged_measure_count: unchanged_count
    }
    result[:identical] = true if identical
    result
  end

  private

  def index_by_key(measures)
    measures.each_with_object({}) do |m, h|
      key = [m[:type], m[:geographical_area], m[:quota_order_number]]
      h[key] = m
    end
  end
end
