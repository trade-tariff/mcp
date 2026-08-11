# frozen_string_literal: true

class NavigateHierarchyShaper < ApplicationShaper
  def initialize(api_response)
    @data     = api_response["data"]
    @included = build_index(api_response["included"] || [])
  end

  def call
    return {} unless @data

    case @data["type"]
    when "chapter" then shape_chapter
    else shape_goods_nomenclature
    end
  end

  private

  def shape_chapter
    attrs = @data["attributes"]
    children_refs = @data.dig("relationships", "headings", "data") || []

    {
      type: "chapter",
      code: attrs["goods_nomenclature_item_id"],
      description: attrs["formatted_description"] || attrs["description"],
      headings: children_refs.filter_map { |ref| shape_child(ref) }
    }.compact
  end

  def shape_goods_nomenclature
    attrs = @data["attributes"]

    {
      code:        attrs["goods_nomenclature_item_id"],
      description: attrs["description"],
      indent:      attrs["number_indents"],
      declarable:  attrs["declarable"]
    }.compact
  end

  def shape_child(ref)
    child = lookup(ref["type"], ref["id"])
    return nil unless child

    child_attrs = child["attributes"]
    {
      code: child_attrs["goods_nomenclature_item_id"],
      description: child_attrs["formatted_description"] || child_attrs["description"],
      indent: child_attrs["number_indents"]
    }.compact
  end
end
