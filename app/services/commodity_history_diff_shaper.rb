# frozen_string_literal: true

class CommodityHistoryDiffShaper
  # Fields that describe the treatment a measure applies. A change to any of them is a
  # change a trader must see. The effective dates are deliberately absent: DBT end-dates
  # and reissues a measure whenever it edits it, so the dates always differ across a
  # reissue even when the treatment itself is unchanged.
  COMPARED_FIELDS = %i[duty unit excise vat reduction_indicator conditions footnotes].freeze

  # Fields that identify which measure is which. Measures are paired on these before
  # their treatment is compared.
  KEY_FIELDS = %i[type geographical_area quota_order_number].freeze

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

    added           = []
    removed         = []
    changed         = []
    unchanged_count = 0

    (from_groups.keys | to_groups.keys).each do |key|
      matched, leftover_from, leftover_to = match_identical(from_groups[key] || [], to_groups[key] || [])
      unchanged_count += matched

      if leftover_from.length == 1 && leftover_to.length == 1
        changed << describe_change(leftover_from.first, leftover_to.first)
      else
        removed.concat(leftover_from)
        added.concat(leftover_to)
      end
    end

    identical = added.empty? && removed.empty? && changed.empty?

    result = {
      commodity_code: @commodity_code,
      from_date: @from_date,
      to_date: @to_date,
      changes: {
        measures_added: added,
        measures_removed: removed,
        measures_changed: changed
      },
      unchanged_measure_count: unchanged_count
    }
    result[:identical] = true if identical
    result
  end

  private

  def group_by_key(measures)
    measures.each_with_object({}) do |m, h|
      key = KEY_FIELDS.map { |f| m[f] }
      (h[key] ||= []) << m
    end
  end

  # Two measures describe the same treatment when every compared field matches.
  def treatment(measure)
    COMPARED_FIELDS.map { |field| comparable(field, measure[field]) }
  end

  # Conditions and footnotes arrive as arrays of hashes. The API does not guarantee their
  # order, so compare them as a sorted set rather than as ordered lists.
  #
  # Footnotes are compared by code alone. DBT rewords footnote descriptions without any
  # change to what a trader must do, and a reworded description is not a change.
  def comparable(field, value)
    return value unless value.is_a?(Array)
    return footnote_codes(value) if field == :footnotes

    value.map(&:to_s).sort
  end

  def footnote_codes(footnotes)
    footnotes.map { |f| f[:code] }.sort
  end

  # Pair measures that share a key by exact treatment.
  # Returns [matched_count, leftover_from_measures, leftover_to_measures].
  def match_identical(from_list, to_list)
    remaining_to  = to_list.dup
    leftover_from = []
    matched       = 0

    from_list.each do |from_m|
      index = remaining_to.index { |to_m| treatment(to_m) == treatment(from_m) }
      if index
        remaining_to.delete_at(index)
        matched += 1
      else
        leftover_from << from_m
      end
    end

    [ matched, leftover_from, remaining_to ]
  end

  def describe_change(from_m, to_m)
    changed_fields = COMPARED_FIELDS.each_with_object({}) do |field, h|
      from_value = comparable(field, from_m[field])
      to_value   = comparable(field, to_m[field])
      next if from_value == to_value

      # Footnotes are reported as code lists, to match how they are compared.
      h[field] = field == :footnotes ? { from: from_value, to: to_value }
                                     : { from: from_m[field], to: to_m[field] }
    end

    {
      type: from_m[:type],
      geographical_area: from_m[:geographical_area],
      quota_order_number: from_m[:quota_order_number],
      from_effective_start_date: from_m[:effective_start_date],
      to_effective_start_date: to_m[:effective_start_date],
      changed_fields: changed_fields
    }.compact
  end
end
