# frozen_string_literal: true

require 'open3'
require_relative '../error'
require_relative '../repository_config'
require_relative 'layout'
require_relative 'paths'
require_relative 'private_git_paths'
require_relative 'private_inventory'

module Shaka
  module Configuration
    # Local report; candidate_config is deliberately omitted from its printable form.
    PrivateSourceResult = Data.define(:root, :common_git_dir, :ref, :trusted_source, :status, :inventory,
                                      :blockers, :candidate_config) do
      def mode = 'private/local'
      def grants_policy? = false
      def grants_merge_authority? = false

      def to_h
        { 'mode' => mode, 'grants_policy' => grants_policy?, 'grants_merge_authority' => grants_merge_authority?,
          'root' => root,
          'common_git_dir' => common_git_dir, 'ref' => ref, 'trusted_source' => trusted_source,
          'status' => status, 'inventory' => inventory.map { |entry| entry.transform_keys(&:to_s) },
          'blockers' => blockers }
      end

      def inspect = "#<#{self.class} mode=#{mode} status=#{status}>"
      alias_method :to_s, :inspect
      def pretty_print(printer) = printer.text(inspect)
    end

    # Read-only preflight of private candidate settings in one Git worktree.
    class PrivateSource
      def initialize(root:, ref:)
        @root = File.realpath(root)
        @ref = ref
        @blockers = []
      end

      def resolve
        verify_worktree!
        sha = resolved_ref
        PrivateGitPaths.verify_trusted_tree!(sha:, git: method(:git))
        trusted = Layout.commit(root: @root, sha:, allow_missing: true, git: PrivateGitPaths.method(:command))
        indexed = indexed_paths
        committed = committed_paths
        inventory = PrivateInventory.new(root: @root, committed:).scan
        @blockers.concat(inventory.blockers)
        inspect_conflicts(trusted, indexed, committed, inventory.entries)
        result(sha, trusted, inventory, load_candidate(inventory, committed))
      end

      private

      def indexed_paths = PrivateGitPaths.parse(git('ls-files', '--cached', '-z')).to_set
      def committed_paths = PrivateGitPaths.committed(root: @root, git: method(:git))

      def resolved_ref
        raise Error, 'Private source ref must be an immutable commit SHA' unless
          @ref.is_a?(String) && @ref.match?(/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/)

        sha = git('rev-parse', '--verify', '--end-of-options', "#{@ref}^{commit}").strip
        raise Error, 'Private source ref must be a full commit SHA' unless sha == @ref

        sha
      end

      def result(sha, trusted, inventory, config)
        status = status_for(inventory, config)
        PrivateSourceResult.new(root: @root, common_git_dir: common_git_dir, ref: sha,
                                trusted_source: trusted ? 'present' : 'absent', status:,
                                inventory: inventory.entries, blockers: @blockers.freeze,
                                candidate_config: status == 'complete' ? config : nil)
      end

      def status_for(inventory, config)
        return 'unsafe_file' if inventory.unsafe
        return 'conflicting' if @conflict
        return 'absent' if inventory.entries.empty?

        @blockers.empty? && config ? 'complete' : 'partial'
      end

      def verify_worktree!
        top = File.realpath(git('rev-parse', '--show-toplevel').strip)
        raise Error, "#{@root} is not the Git worktree root" unless top == @root
      end

      def common_git_dir = File.realpath(File.expand_path(git('rev-parse', '--git-common-dir').strip, @root))

      def git(*args)
        output, error, status = PrivateGitPaths.capture(@root, *args)
        raise Error, "Cannot inspect private source: git #{args.first} failed: #{error.strip}" unless status.success?

        output
      end

      def inspect_conflicts(trusted, indexed, committed, entries)
        conflict!("#{Paths::CONTRACT} conflicts with private #{Paths::NEW_CONTRACT}") if legacy_collision?(entries)
        private_tracked = (indexed | committed).select { |path| PrivateInventory.private_path?(root: @root, path:) }
        conflict!("tracked private files: #{private_tracked.join(', ')}") unless private_tracked.empty?
        conflict!("Trusted default branch already has #{trusted.contract}") if trusted && entries.any?
      end

      def legacy_collision?(entries)
        legacy = File.join(@root, Paths::CONTRACT)
        entries.any? && (File.exist?(legacy) || File.symlink?(legacy))
      end

      def conflict!(message)
        @blockers << message
        @conflict = true
      end

      def load_candidate(inventory, committed)
        return if inventory.unsafe || @conflict

        entries = inventory.entries
        return if entries.empty?

        unless entries.any? { |entry| entry[:path] == Paths::NEW_CONTRACT && entry[:type] == 'regular' }
          @blockers << "Missing #{Paths::NEW_CONTRACT}"
          return
        end

        validate_candidate(committed)
      end

      def validate_candidate(committed)
        config = RepositoryConfig.load(root: @root)
        inspect_optional_pair(config)
        inspect_prompt_dependencies(config, committed)
        config
      rescue Error, SystemCallError, ArgumentError => e
        @blockers << e.message
        nil
      end

      def inspect_optional_pair(config)
        return if config.commands.key?('validate_local') == config.commands.key?('trigger_hosted_ci')

        @blockers << 'Private validate-local and trigger-hosted-ci must be present together'
      end

      def inspect_prompt_dependencies(config, committed)
        RepositoryConfig.prompt_files(review: config.review, opening: config.opening_check).each do |label, path|
          @blockers << "#{label} #{path} lacks a candidate HEAD commit" unless
            committed_prompt?(path, committed)
        end
      end

      def committed_prompt?(path, committed)
        private_root = File.join(@root, PrivateInventory::DIRECTORY)
        return true if File.expand_path(path, @root).start_with?("#{private_root}/")

        PrivatePathHops.committed_path?(root: @root, path:, committed:)
      end
    end
  end
end
