# frozen_string_literal: true

require 'open3'
require_relative 'repository_config'
require_relative 'review_prompt'
require_relative 'trusted_path_resolver'
require_relative 'configuration/layout'
require_relative 'configuration/sources'

module Shaka
  # Reads repository policy from an immutable commit resolved from a trusted ref.
  class TrustedConfigSource
    include Configuration::Sources

    def self.load(root:, ref: nil, candidate_commands: true)
      return RepositoryConfig.load(root:) unless ref

      new(root:, candidate_commands:).load(ref)
    end

    # PR commands read policy only from a trusted ref; without one they keep GitHub's native gates
    # instead of falling back to the candidate file.
    def self.from_ref(root:, ref:)
      load(root:, ref:) if ref
    end

    def initialize(root:, candidate_commands: true)
      @root = root
      @candidate_commands = candidate_commands
    end

    def load(ref)
      sha = resolve(ref)
      layout = Configuration::Layout.commit(root: @root, sha:, allow_missing: true) || Configuration::Layout::LEGACY
      source = read_at_commit(root: @root, sha:, path: layout.contract, display_ref: ref)
      config = RepositoryConfig.load(root: @root, source:, available_commands: optional_commands(sha, layout), sha:,
                                     candidate_commands: @candidate_commands)
      validate_prompt_files(config.review, config.opening_check, sha)
      config
    end

    def opening_prompt(config)
      path = config.opening_check['prompt_file']
      return unless path

      resolved, = TrustedPathResolver.new(root: @root, sha: config.sha).resolve(path)
      git_output(config.sha, resolved, '-p')
    end

    private

    # A prompt file the review runner would reject would stop every local review, including the one
    # for the PR that fixes it.
    def validate_prompt_files(review, opening, sha)
      resolver = TrustedPathResolver.new(root: @root, sha:)
      RepositoryConfig.prompt_files(review:, opening:).each do |label, path|
        resolved, entry = resolver.resolve(path)
        is_blob = entry && entry.last == 'blob' && entry.first != TrustedPathResolver::SYMLINK.first
        raise Error, "#{label} does not name a file at #{sha}: #{path}" unless is_blob

        error = ReviewPrompt.file_error(git_output(sha, resolved, '-s').to_i) { git_output(sha, resolved, '-p') }
        raise Error, "#{label} #{path} at #{sha} #{error}" if error
      end
    end

    # `-s` prints the blob size and `-p` its contents.
    def git_output(sha, path, option)
      text, error, status = Open3.capture3('git', '-C', @root, 'cat-file', option, "#{sha}:#{path}", binmode: true)
      raise Error, "Cannot read #{path} at #{sha}: #{error.strip}" unless status.success?

      text
    end

    def resolve(ref)
      arguments = ['git', '-C', @root, 'rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}"]
      sha, error, status = Open3.capture3(*arguments)
      raise Error, "Invalid trusted ref #{ref}: #{error.strip}" unless status.success?

      sha.strip
    end

    def optional_commands(sha, layout)
      validate_command_directory(sha, layout)
      resolver = TrustedPathResolver.new(root: @root, sha:)
      validate_required_commands(resolver, sha, layout)
      entries = command_entries(resolver, layout)
      validate_legacy_command_entries(resolver, entries, sha, layout)
      layout.optional.filter_map do |name, path|
        next unless entries.key?(path)

        validate_command_entry(entries.fetch(path), path, sha, resolver)
        name
      end
    end

    def validate_required_commands(resolver, sha, layout)
      layout.required.each_value do |path|
        entry = resolver.entry(path)
        raise Error, "#{path} is missing at trusted ref #{sha}" unless entry

        validate_command_entry(entry, path, sha, resolver)
      end
    end

    def validate_command_directory(sha, layout)
      directory = layout.command_directory
      type, error, status = Open3.capture3('git', '-C', @root, 'cat-file', '-t', "#{sha}:#{directory}")
      return if status.success? && type.strip == 'tree'
      raise Error, "#{directory} at #{sha} must be a real directory, not a symlink" if status.success?

      raise Error, "Cannot inspect #{directory} at #{sha}: #{error.strip}"
    end

    def command_entries(resolver, layout)
      layout.optional.values.to_h do |path|
        [path, resolver.entry(path)]
      end.compact
    end

    def validate_legacy_command_entries(resolver, entries, sha, layout)
      layout.legacy_optional.each do |name, legacy_path|
        fixed_path = layout.optional.fetch(name)
        next unless resolver.entry(legacy_path) && !entries.key?(fixed_path)

        raise Error, "#{legacy_path} requires the standard entry point #{fixed_path} at trusted ref #{sha}"
      end
    end

    def validate_command_entry(entry, path, sha, resolver)
      mode, type = entry
      return if type == 'blob' && mode == '100755'
      return validate_symlink_target(path, sha, resolver) if type == 'blob' && mode == '120000'

      raise Error, "#{path} at #{sha} must be an executable file or symlink"
    end

    def validate_symlink_target(path, sha, resolver)
      resolved, entry = resolver.resolve(path)
      return if entry == %w[100755 blob]

      raise Error, "#{path} at #{sha} must target a tracked executable file: #{resolved}"
    end
  end
end
