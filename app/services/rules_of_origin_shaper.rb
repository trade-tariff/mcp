# frozen_string_literal: true

class RulesOfOriginShaper
  def self.call(api_response)
    new(api_response).call
  end

  def initialize(api_response)
    @data = api_response["data"] || []
  end

  def call
    @data.map { |scheme| shape_scheme(scheme) }
  end

  private

  def shape_scheme(scheme)
    attrs = scheme["attributes"]
    {
      scheme_code: attrs["scheme_code"],
      title: attrs["title"],
      unilateral: attrs["unilateral"],
      proof_of_origin: attrs["proof_of_origin"]
    }.compact
  end
end
