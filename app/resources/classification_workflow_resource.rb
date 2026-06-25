# frozen_string_literal: true

class ClassificationWorkflowResource < ApplicationResource
  class << self
    def resource
      MCP::Resource.new(
        uri: "tariff://classification-workflow",
        name: "classification-workflow",
        description: "Step-by-step reasoning guide for classifying goods into UK commodity codes. " \
                     "Read this before helping a trader find a commodity code, tariff code, or classification " \
                     "for customs declarations. Covers the classification process, output format, duty rates, " \
                     "licensing requirements, and how to use the live tariff tools in connected mode.",
        mime_type: "text/markdown"
      )
    end

    private

    def filename
      "classification_workflow.md"
    end
  end
end
