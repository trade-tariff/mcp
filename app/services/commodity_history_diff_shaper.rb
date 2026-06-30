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
    from_groups = group_by_key(@from_measures)
    to_groups   = group_by_key(@to_measures)

    added        = []
    removed      = []
    duty_changes = []
    unchanged_count = 0

    (from_groups.keys | to_groups.keys).each do |key|
      from_list = from_groups[key] || []
      to_list   = to_groups[key]   || []

      if from_list.length == 1 && to_list.length == 1
        from_m = from_list.first
        to_m   = to_list.first

        if from_m[:duty] == to_m[:duty]
          unchanged_count += 1
        else
          duty_changes << {
            type: from_m[:type],
            geographical_area: from_m[:geographical_area],
            quota_order_number: from_m[:quota_order_number],
            from: from_m[:duty],
            to: to_m[:duty]
          }.compact
        end
      else
        matched, leftover_from, leftover_to = match_by_duty(from_list, to_list)
        unchanged_count += matched
        removed.concat(leftover_from)
        added.concat(leftover_to)
      end
    end

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

  def group_by_key(measures)
    measures.each_with_object({}) do |m, h|
      key = [ m[:type], m[:geographical_area], m[:quota_order_number] ]
      (h[key] ||= []) << m
    end
  end

  # Multiset-match measures between from_list and to_list by exact duty value.
  # Returns [matched_count, leftover_from_measures, leftover_to_measures]
  def match_by_duty(from_list, to_list)
    remaining_to = to_list.dup
    leftover_from = []
    matched = 0

    from_list.each do |from_m|
      idx = remaining_to.index { |to_m| to_m[:duty] == from_m[:duty] }
      if idx
        remaining_to.delete_at(idx)
        matched += 1
      else
        leftover_from << from_m
      end
    end

    [ matched, leftover_from, remaining_to ]
  end
end
