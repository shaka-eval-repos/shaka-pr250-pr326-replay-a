# frozen_string_literal: true

require_relative '../error'
require_relative '../merge_limits'
require_relative 'validation'

module Shaka
  class RepositoryConfig
    # Validates merge authority, size limits, and the checks that gate merge when GitHub enforces none.
    class MergeSchema
      include Validation

      REQUIRED_CHECKS = 'required_checks'

      def initialize(merge)
        @merge = merge
      end

      def validate
        mapping!(@merge, 'merge')
        retired = %w[method release].find { |key| @merge.key?(key) }
        raise Error, "merge.#{retired} is no longer configurable; see skills/shaka/references/migration.md" if retired

        keys!(@merge, ['preference'], ['limits', REQUIRED_CHECKS], 'merge')
        enum!(@merge['preference'], %w[ask auto], 'merge.preference must be ask or auto')
        MergeLimits.validate!(@merge['limits']) if @merge.key?('limits')
        name_list!(@merge[REQUIRED_CHECKS], "merge.#{REQUIRED_CHECKS}", 'check names') if @merge.key?(REQUIRED_CHECKS)
      end
    end
  end
end
