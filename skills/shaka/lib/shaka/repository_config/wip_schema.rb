# frozen_string_literal: true

require_relative '../error'
require_relative 'validation'

module Shaka
  class RepositoryConfig
    # Validates the optional WIP Details policy.
    class WipSchema
      include Validation

      KEYS = %w[include_locations].freeze

      def initialize(wip)
        @wip = wip
      end

      def validate
        mapping!(@wip, 'wip')
        keys!(@wip, [], KEYS, 'wip')
        @wip.each do |key, value|
          enum!(value, [true, false], "wip.#{key} must be true or false")
        end
      end
    end
  end
end
