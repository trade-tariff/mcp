# frozen_string_literal: true

class ServiceNormaliser
  XI_ALIASES = %w[xi ni northern\ ireland northern_ireland].freeze

  def self.call(input)
    return "uk" if input.nil? || input.strip.empty?

    XI_ALIASES.include?(input.strip.downcase) ? "xi" : "uk"
  end
end
