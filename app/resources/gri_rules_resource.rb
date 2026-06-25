# frozen_string_literal: true

class GriRulesResource < ApplicationResource
  class << self
    def resource
      MCP::Resource.new(
        uri: "tariff://gri-rules",
        name: "gri-rules",
        description: "The six General Rules of Interpretation (GRI) — the legal framework for classifying " \
                     "goods in the UK Tariff. Apply these rules in numerical order to resolve ambiguous " \
                     "classifications. Most goods classify under GRI 1 alone. These rules are international " \
                     "law (Harmonized System) and do not change.",
        mime_type: "text/markdown"
      )
    end

    private

    def filename
      "gri_rules.md"
    end
  end
end
