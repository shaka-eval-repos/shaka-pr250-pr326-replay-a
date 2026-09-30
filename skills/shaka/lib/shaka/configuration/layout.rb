# frozen_string_literal: true

require 'open3'
require_relative '../error'
require_relative '../trusted_path_resolver'
require_relative 'paths'

module Shaka
  module Configuration
    # One source snapshot chooses the contract and its complete command directory.
    class Layout
      Selection = Data.define(:policy, :candidate)

      attr_reader :contract, :command_directory, :required, :optional, :legacy_optional

      def initialize(contract:, command_directory:, required:, optional:, legacy_optional:)
        @contract = contract
        @command_directory = command_directory
        @required = required
        @optional = optional
        @legacy_optional = legacy_optional
      end

      def commands = required.merge(optional)

      LEGACY = new(contract: Paths::CONTRACT, command_directory: Paths::COMMAND_DIRECTORY,
                   required: Paths::REQUIRED_COMMANDS, optional: Paths::OPTIONAL_COMMANDS,
                   legacy_optional: Paths::LEGACY_OPTIONAL_COMMANDS).freeze
      NEW = new(contract: Paths::NEW_CONTRACT, command_directory: Paths::NEW_COMMAND_DIRECTORY,
                required: Paths::NEW_REQUIRED_COMMANDS, optional: Paths::NEW_OPTIONAL_COMMANDS,
                legacy_optional: Paths::NEW_LEGACY_OPTIONAL_COMMANDS).freeze

      def self.worktree(root:, allow_missing: false)
        validate_root_directory!(root)
        present = [LEGACY, NEW].select { |layout| entry?(File.join(root, layout.contract)) }
        chosen = select(present, allow_missing:)
        validate_worktree!(root, chosen) if chosen
        chosen
      end

      def self.validate_root_directory!(root)
        directory = File.join(root, Paths::DIRECTORY)
        raise Error, "#{Paths::DIRECTORY} must be a real directory, not a symlink" if File.symlink?(directory)
        return unless File.exist?(directory)
        return if File.directory?(directory)

        raise Error, "#{Paths::CONTRACT} cannot be read: #{Paths::DIRECTORY} is not a real directory"
      end

      def self.validate_worktree!(root, chosen)
        directories = [Paths::DIRECTORY, File.dirname(chosen.contract)].uniq
        directories.each do |relative|
          path = File.join(root, relative)
          raise Error, "#{relative} must be a real directory, not a symlink" if File.symlink?(path)
        end

        return if File.file?(File.join(root, chosen.contract)) && !File.symlink?(File.join(root, chosen.contract))

        raise Error, "#{chosen.contract} must be a regular file"
      end

      def self.commit(root:, sha:, allow_missing: false, git: nil)
        git ||= ->(*arguments) { Open3.capture3('git', *arguments) }
        present = [LEGACY, NEW].select do |layout|
          _out, _error, status = git.call('-C', root, 'cat-file', '-e', "#{sha}:#{layout.contract}")
          status.success?
        end
        chosen = select(present, allow_missing:)
        validate_commit!(root, sha, chosen, git) if chosen
        chosen
      end

      def self.validate_commit!(root, sha, chosen, git)
        entry = TrustedPathResolver.new(root:, sha:, git:).entry(chosen.contract)
        return if entry && entry.last == 'blob' && entry.first != TrustedPathResolver::SYMLINK.first

        raise Error, "#{chosen.contract} at #{sha} must be a regular file"
      end

      def self.select(present, allow_missing:)
        raise Error, "Both #{LEGACY.contract} and #{NEW.contract} exist" if present.length == 2
        return present.first if present.any?
        return if allow_missing

        raise Error, "Cannot find #{LEGACY.contract} or #{NEW.contract}"
      end

      def self.entry?(path)
        File.lstat(path)
        true
      rescue Errno::ENOENT, Errno::ENOTDIR
        false
      end
    end
  end
end
