# frozen_string_literal: true

module Shaka
  # Repository-facing names belong here; packaged workflow data is separate.
  module Configuration
    # Literal names for repository and machine configuration entry points.
    module Paths
      DIRECTORY = '.agents'
      COMMAND_DIRECTORY = '.agents/bin'
      CONTRACT = '.agents/agent-workflow.yml'
      POINTER = '.agents/shaka.md'
      LEGACY_README = '.agents/README.md'
      REPOSITORY_ALLOWLIST = '.agents/trusted-github-actors.yml'
      NEW_CONTRACT = '.agents/shaka/config.yml'
      PRIVATE_EXCLUDE_PATTERN = '/.agents/shaka/'
      NEW_COMMAND_DIRECTORY = '.agents/shaka/bin'
      NEW_REPOSITORY_ALLOWLIST = '.agents/shaka/trusted-github-actors.yml'
      MACHINE_ALLOWLIST = '~/.agents/trusted-github-actors.yml'

      REQUIRED_COMMANDS = {
        'setup' => '.agents/bin/setup',
        'validate' => '.agents/bin/validate',
        'test' => '.agents/bin/test'
      }.freeze
      OPTIONAL_COMMANDS = {
        'validate_local' => '.agents/bin/validate-local',
        'trigger_hosted_ci' => '.agents/bin/trigger-hosted-ci'
      }.freeze
      LEGACY_OPTIONAL_COMMANDS = {
        'validate_local' => '.agents/bin/validate_local',
        'trigger_hosted_ci' => '.agents/bin/trigger_hosted_ci'
      }.freeze
      COMMANDS = REQUIRED_COMMANDS.merge(OPTIONAL_COMMANDS).freeze
      NEW_REQUIRED_COMMANDS = REQUIRED_COMMANDS.transform_values do |path|
        path.sub(COMMAND_DIRECTORY, NEW_COMMAND_DIRECTORY)
      end.freeze
      NEW_OPTIONAL_COMMANDS = OPTIONAL_COMMANDS.transform_values do |path|
        path.sub(COMMAND_DIRECTORY, NEW_COMMAND_DIRECTORY)
      end.freeze
      NEW_LEGACY_OPTIONAL_COMMANDS = LEGACY_OPTIONAL_COMMANDS.transform_values do |path|
        path.sub(COMMAND_DIRECTORY, NEW_COMMAND_DIRECTORY)
      end.freeze
      REPOSITORY_NAMES = {
        DIRECTORY: DIRECTORY, COMMAND_DIRECTORY: COMMAND_DIRECTORY, CONTRACT: CONTRACT,
        POINTER: POINTER, LEGACY_README: LEGACY_README, REPOSITORY_ALLOWLIST: REPOSITORY_ALLOWLIST
      }.freeze
      GENERATED_FILES = [CONTRACT, POINTER, LEGACY_README, *COMMANDS.values,
                         NEW_CONTRACT, *NEW_REQUIRED_COMMANDS.values, *NEW_OPTIONAL_COMMANDS.values].freeze

      def self.at(root, relative) = File.join(root, relative)
    end
  end
end
