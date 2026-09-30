# frozen_string_literal: true

require_relative '../error'
require_relative '../configuration/layout'
require_relative 'validation'

module Shaka
  class RepositoryConfig
    # Validates the fixed command interface and returns its effective paths.
    class CommandSchema
      include Validation

      def initialize(root:, available_commands: nil, candidate_commands: true,
                     layout: Configuration::Layout::LEGACY, candidate_layout: layout)
        @root = root
        @available_commands = available_commands
        @candidate_commands = candidate_commands
        @layout = layout
        @candidate_layout = candidate_layout
      end

      def validate
        commands = validate_names(@layout.required.keys + available_optional_commands)
        validate_candidate_optional_commands
        commands
      end

      def validate_available_optional_commands
        validate_names(available_optional_commands)
      end

      private

      def validate_names(names)
        return trusted_names(names) unless @candidate_commands

        validate_interface_directory
        validate_legacy_optional_paths
        validate_dependencies(names)
        names.to_h do |name|
          path = @candidate_layout.commands.fetch(name)
          executable!(path, path)
          [name, path]
        end.freeze
      end

      def trusted_names(names)
        validate_dependencies(names)
        trusted_commands(names)
      end

      def trusted_commands(names)
        names.to_h { |name| [name, @layout.commands.fetch(name)] }.freeze
      end

      def validate_interface_directory
        [Configuration::Paths::DIRECTORY, File.dirname(@candidate_layout.contract),
         @candidate_layout.command_directory].uniq.each do |relative|
          path = File.join(@root, relative)
          raise Error, "#{relative} must be a real directory, not a symlink" if File.symlink?(path)
        end
      end

      def available_optional_commands
        return @available_commands & @layout.optional.keys if @available_commands

        @layout.optional.keys.select do |name|
          command_entry?(@candidate_layout.optional.fetch(name))
        end
      end

      def validate_candidate_optional_commands
        return unless @candidate_commands && @available_commands

        names = @candidate_layout.optional.filter_map { |name, path| name if command_entry?(path) }
        validate_dependencies(names)
        names.each do |name|
          path = @candidate_layout.optional.fetch(name)
          executable!(path, path)
        end
      end

      def command_entry?(relative)
        path = File.join(@root, relative)
        File.exist?(path) || File.symlink?(path)
      end

      def validate_dependencies(names)
        return unless names.include?('trigger_hosted_ci') && !names.include?('validate_local')

        trigger = @candidate_layout.optional.fetch('trigger_hosted_ci')
        local = @candidate_layout.optional.fetch('validate_local')
        raise Error, "#{trigger} requires #{local}"
      end

      def validate_legacy_optional_paths
        @candidate_layout.legacy_optional.each do |name, legacy_path|
          fixed_path = @candidate_layout.optional.fetch(name)
          next unless command_entry?(legacy_path) && !command_entry?(fixed_path)

          raise Error, "#{legacy_path} requires the standard entry point #{fixed_path}"
        end
      end
    end
  end
end
