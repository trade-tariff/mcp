# frozen_string_literal: true

class ServiceNormaliser
  UK_ALIASES = ["uk", "gb", "great britain", "united kingdom"].freeze
  XI_ALIASES = ["xi", "ni", "northern ireland", "northern_ireland"].freeze

  def self.call(input)
    return "uk" if input.nil? || input.strip.empty?

    normalised = input.strip.downcase

    return "uk" if UK_ALIASES.include?(normalised)
    return "xi" if XI_ALIASES.include?(normalised)

    raise ArgumentError, "Unknown service: '#{input}'. Use 'uk' for Great Britain or 'xi'/'ni'/'northern ireland' for Northern Ireland."
  end
end
