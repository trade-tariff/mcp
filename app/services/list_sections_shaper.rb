# frozen_string_literal: true

class ListSectionsShaper
  def self.call(api_response)
    (api_response["data"] || []).map do |item|
      attrs = item["attributes"]
      from  = attrs["chapter_from"]
      to    = attrs["chapter_to"]
      {
        numeral: attrs["numeral"],
        title: attrs["title"],
        chapters: from == to ? from : "#{from}-#{to}"
      }.compact
    end
  end
end
