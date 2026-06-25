# frozen_string_literal: true

class ApplicationResource
  RESOURCES_PATH = Rails.root.join("app/resources")

  class << self
    def resource
      raise NotImplementedError, "#{name} must implement .resource"
    end

    def content
      RESOURCES_PATH.join(filename).read
    end

    private

    def filename
      raise NotImplementedError, "#{name} must implement .filename"
    end
  end
end
