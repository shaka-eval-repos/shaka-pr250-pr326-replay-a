# frozen_string_literal: true

require_relative '../error'
require_relative 'validation'

module Shaka
  class RepositoryConfig
    # Validates the optional feature-branch layout.
    class BranchSchema
      include Validation

      PLACEHOLDERS = %w[login host issue description].freeze

      def initialize(data)
        @data = data
      end

      def validate
        mapping = mapping!(@data, 'branches')
        keys!(mapping, ['name'], [], 'branches')
        name = string!(mapping['name'], 'branches.name')
        raise Error, 'branches.name must include {issue}' unless name.include?('{issue}')

        leftover = name.scan(/\{([^{}]+)\}/).flatten - PLACEHOLDERS
        raise Error, "branches.name has unknown placeholder: #{leftover.first}" unless leftover.empty?
      end
    end
  end
end
