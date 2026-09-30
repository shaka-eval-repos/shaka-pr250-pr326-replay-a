# frozen_string_literal: true

# Validates the optional opening-check settings in the repository contract.

require_relative 'validation'

module Shaka
  class RepositoryConfig
    # Validates the external reviewer choice and optional trusted custom prompt path.
    class OpeningSchema
      include Validation

      def initialize(opening)
        @opening = opening
      end

      def validate
        mapping!(@opening, 'opening_check')
        keys!(@opening, [], %w[external_enabled prompt_file], 'opening_check')
        if @opening.key?('external_enabled')
          enum!(@opening['external_enabled'], [true, false],
                'opening_check.external_enabled must be true or false')
        end
        return unless @opening.key?('prompt_file')

        prompt_path!(@opening['prompt_file'], 'opening_check.prompt_file')
      end
    end
  end
end
