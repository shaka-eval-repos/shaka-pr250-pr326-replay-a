# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'securerandom'
require 'time'
require_relative '../configuration/private_inventory'
require_relative '../configuration/private_git_paths'
require_relative '../error'

module Shaka
  class Seam
    # Clone-local, worktree-specific copies. They are for comparison, never activation.
    class PrivateRecovery
      DIRECTORY = 'shaka/private-worktrees'
      PRIVATE_DIRECTORY = Configuration::PrivateInventory::DIRECTORY

      attr_reader :root, :common_git_dir, :storage

      def initialize(root:, assign_identity: true)
        @root = File.realpath(root)
        top = git('rev-parse', '--show-toplevel').strip
        raise Error, "#{root} is not a Git worktree root" unless File.realpath(top) == @root

        @common_git_dir = File.realpath(File.expand_path(git('rev-parse', '--git-common-dir').strip, @root))
        git_dir = File.realpath(File.expand_path(git('rev-parse', '--git-dir').strip, @root))
        @storage = storage_for(git_dir, assign_identity)
      end

      def storage_for(git_dir, assign_identity)
        identity = assign_identity ? assigned_identity(git_dir) : existing_identity(git_dir)
        File.join(@common_git_dir, DIRECTORY, identity) if identity
      end

      private :storage_for

      def adoption_paths
        indexed = Configuration::PrivateGitPaths.parse(git('ls-files', '--cached', '-z'))
        committed = Configuration::PrivateGitPaths.committed(root: @root, git: method(:git)).to_a
        (indexed | committed).select do |path|
          path == Configuration::Paths::CONTRACT ||
            Configuration::PrivateInventory.private_path?(root: @root, path:)
        end.sort
      end

      def inspect_checkout
        tree = File.join(@root, PRIVATE_DIRECTORY)
        assert_safe_tree!(tree)
        adopted = adoption_paths
        return report('adopted', adopted, compare_with_checkout) if adopted.any?

        return report('partial', [], compare_with_checkout) if File.directory?(tree) && !complete_tree?

        refresh_from_checkout(tree) if File.directory?(tree)
        report(File.directory?(tree) ? 'private' : 'absent', [], compare_with_checkout)
      end

      def list
        base = File.join(@common_git_dir, DIRECTORY)
        return [] unless File.directory?(base)

        Dir.children(base).sort.filter_map do |id|
          next unless id.match?(/\A[0-9a-f]{64}\z/)

          read_manifest(base, id)
        end
      end

      private

      def git(*)
        output, error, status = Configuration::PrivateGitPaths.capture(@root, *)
        raise Error, "Cannot inspect Git: #{error.strip}" unless status.success?

        output
      end

      def report(status, adopted, changed)
        { 'status' => status, 'recovery' => @storage, 'adoption_paths' => adopted, 'changed' => changed,
          'hidden_untracked' => adopted.empty? ? [] : hidden_untracked(adopted),
          'current' => File.directory?(File.join(@storage, 'current')),
          'previous' => File.directory?(File.join(@storage, 'previous')) }
      end

      def safe_inventory
        committed = Configuration::PrivateGitPaths.committed(root: @root, git: method(:git))
        result = Configuration::PrivateInventory.new(root: @root, committed:).scan
        raise Error, "Unsafe private tree: #{result.blockers.join('; ')}" if result.unsafe

        result.entries
      end

      def assert_safe_tree!(tree)
        [File.dirname(tree), tree].each do |path|
          next unless File.symlink?(path) || (File.exist?(path) && !File.directory?(path))

          raise Error, "Unsafe private directory: #{path}"
        end
      end

      def refresh_from_checkout(tree)
        with_storage_lock do
          safe_inventory
          save_from(tree) if current_inventory != inventory_for(tree)
        end
      end

      def read_manifest(base, id)
        directory = File.join(base, id)
        current = File.directory?(File.join(directory, 'current'))
        previous = File.directory?(File.join(directory, 'previous'))
        return unless current || previous

        manifest_data(File.join(directory, 'manifest.json')).merge('id' => id, 'current' => current,
                                                                   'previous' => previous)
      end

      def manifest_data(path)
        return {} unless File.file?(path) && !File.symlink?(path)

        data = JSON.parse(File.read(path))
        data.is_a?(Hash) ? data : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end

require_relative 'private_recovery/preparation'
require_relative 'private_recovery/copies'
require_relative 'private_recovery/rotation'
require_relative 'private_recovery/identity'
require_relative 'private_recovery/inventory'
require_relative 'private_recovery/exclusion'
