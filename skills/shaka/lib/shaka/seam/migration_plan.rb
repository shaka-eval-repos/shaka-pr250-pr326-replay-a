# frozen_string_literal: true

require 'open3'
require 'shellwords'
require_relative '../repository_config'
require_relative '../configuration'
require_relative 'field_classifier'
require_relative 'migration_policy'

module Shaka
  class Seam
    # Command inventory, collisions, and leftover adapters for a migrate report.
    module MigrationCommands
      private

      def command_report
        {
          'commands' => command_inventory,
          'command_collisions' => command_collisions,
          'adapters_eligible_for_removal' => adapters_eligible_for_removal
        }
      end

      def command_inventory
        Configuration::Paths::COMMANDS.to_h do |name, path|
          [name, { 'path' => path, 'present_at_from_ref' => command_present?(path) }]
        end
      end

      def command_present?(path)
        Configuration.entry_at_commit?(root:, sha: @sha, path:)
      end

      def command_collisions
        mapping = command_mapping
        return [] unless mapping

        Configuration::Paths::COMMANDS.keys.filter_map { |role| collision_for(role, mapping) }
      end

      def command_mapping
        @data['commands'] if @data.is_a?(Hash) && @data['commands'].is_a?(Hash)
      end

      def collision_for(role, mapping)
        expected = Configuration::Paths::COMMANDS.fetch(role)
        actual = mapping[role]
        return if actual.nil? || actual == expected

        { 'role' => role, 'mapped_path' => actual, 'temporary_behavior' => collision_behavior(role, mapping) }
      end

      def collision_behavior(role, mapping)
        return setup_collision_behavior(mapping.fetch(role)) if role == 'setup'
        return optional_collision_behavior(role, mapping.fetch(role)) if optional_role?(role)

        targets = [mapping['validate'], mapping['test']].compact.uniq.join(' and ')
        'Until the new seam is trusted, use the stricter superset: both ' \
          "#{Configuration::Paths::REQUIRED_COMMANDS.fetch('validate')} and " \
          "#{Configuration::Paths::REQUIRED_COMMANDS.fetch('test')} must execute #{targets}"
      end

      def optional_role?(role)
        Configuration::Paths::OPTIONAL_COMMANDS.key?(role)
      end

      def setup_collision_behavior(actual)
        "Keep #{actual} reachable from #{Configuration::Paths::REQUIRED_COMMANDS.fetch('setup')} " \
          'until the new seam is trusted'
      end

      def optional_collision_behavior(role, actual)
        expected = Configuration::Paths::OPTIONAL_COMMANDS.fetch(role)
        "Keep #{actual} reachable from #{expected} until the new seam is trusted"
      end

      def require_optional_entry_points(classified)
        mapping = command_mapping
        return unless mapping

        Configuration::Paths::OPTIONAL_COMMANDS.each do |role, path|
          next unless mapping.key?(role)
          next if Configuration.command_file?(root, role)

          classified.blocking << path
        end
      end

      def adapters_eligible_for_removal
        mapping = command_mapping
        return [] unless mapping

        Configuration::Paths::COMMANDS.filter_map do |role, expected|
          actual = mapping[role]
          actual if actual.is_a?(String) && actual != expected
        end
      end
    end

    # Deterministic migrate report from a predecessor YAML document.
    module MigrationPlan
      include MigrationPolicy
      include MigrationCommands

      private

      def build_report
        classified = FieldClassifier.new(@data).call
        overlay_explicit_policy(classified)
        reject_invalid_review(classified)
        reject_invalid_merge(classified)
        require_optional_entry_points(classified)
        report_body(classified)
      end

      def reject_invalid_review(classified)
        review = classified.established['review']
        return unless review.is_a?(Hash)

        RepositoryConfig::ReviewSchema.new(review).validate
      rescue Error => e
        classified.blocking << e.message
      end

      # A missing preference is already blocking; validate the rest once it is established.
      def reject_invalid_merge(classified)
        merge = classified.established['merge']
        return unless merge.is_a?(Hash) && merge.key?('preference')

        RepositoryConfig::MergeSchema.new(merge).validate
      rescue Error => e
        classified.blocking << e.message
      end

      def report_body(classified)
        {
          'mode' => @options[:apply] ? 'apply' : 'plan',
          'from_ref' => @sha,
          'retained' => classified.retained,
          'moved_to_agents' => classified.moved_to_agents,
          'moved_to_operational_config' => classified.moved_to_operational_config,
          'retired' => classified.retired,
          'blocking' => classified.blocking,
          'established' => classified.established
        }.merge(command_report, validation_report)
      end

      def validation_report
        {
          'validation' => validation_notes,
          'rollback' => rollback_recipe
        }
      end

      def rollback_recipe
        restore = "git -C #{Shellwords.escape(root)} checkout #{@sha} -- #{Configuration::Paths::CONTRACT}"
        pointer = Configuration::Paths::POINTER
        return "#{restore} #{pointer}" if command_present?(pointer)

        "#{restore} && rm -f #{Shellwords.escape(Configuration.path(root, :POINTER))}"
      end

      def validation_notes
        {
          'previous_trusted_ref' =>
            "required before merge with the previous Shaka installation: shaka seam check --root #{root} --ref #{@sha}",
          'candidate_local' =>
            "target Shaka candidate check (grants no authority): shaka seam check --root #{root} --local"
        }
      end
    end
  end
end
