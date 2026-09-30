# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'pathname'
require_relative '../configuration'
require_relative '../configuration/wrapper_template'
require_relative 'upgrade_plan/inventory'
require_relative 'upgrade_plan/command_repair'
require_relative 'upgrade_plan/root_repair'
require_relative 'upgrade_plan/reference_patterns'
require_relative 'upgrade_plan/symlink_chain'
require_relative 'upgrade_plan/reference_dependencies'
require_relative 'upgrade_plan/indexed_references'
require_relative 'upgrade_plan/private_tools'
require_relative 'upgrade_plan/continued_references'
require_relative 'upgrade_plan/references'

module Shaka
  class Seam
    # A complete, deterministic inventory. No method in this class writes to the checkout.
    class UpgradePlan
      PATHS = Configuration::Paths
      OLD_ROOT = 'root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)'
      GIT_ROOT = Configuration::WrapperTemplate::SHELL_ROOT
      RUBY_GIT_ROOT = "IO.popen({ 'GIT_DIR' => nil, 'GIT_WORK_TREE' => nil, 'GIT_COMMON_DIR' => nil, " \
                      "'GIT_PREFIX' => nil, 'GIT_CEILING_DIRECTORIES' => nil }, " \
                      "['git', '-C', __dir__, 'rev-parse', '--show-toplevel'], " \
                      '&:read).delete_suffix("\\n")'

      include Inventory
      include CommandRepair
      include RootRepair
      include ReferencePatterns
      include SymlinkChain
      include ReferenceDependencies
      include IndexedReferences
      include PrivateTools
      include ContinuedReferences
      include References

      attr_reader :changes, :blockers, :report

      def initialize(root)
        @root = root
        @changes = []
        @blockers = []
        @references = []
        @links = []
        @repairs = []
        @moves = []
      end

      def build
        preflight_directories
        layout = Configuration::Layout.worktree(root: @root, allow_missing: true)
        inventory(layout)
        scan_reference_inventory if layout == Configuration::Layout::LEGACY
        dirty_overlap
        finish_report(layout)
      rescue Shaka::Error => e
        @blockers << "#{e.message}; resolve the partial migration before retrying"
        finish_report(nil)
      end

      def finish_report(layout)
        @report = {
          'mode' => 'preview', 'status' => status(layout), 'moves' => @moves.sort_by { |item| item['from'] },
          'repairs' => @repairs.sort_by { |item| item['path'] },
          'symlinks' => @links.sort_by { |item| item['from'] },
          'references' => @references.sort_by { |item| item['path'] },
          'blockers' => @blockers.uniq.sort,
          'validation' => ['shaka seam check --root DIR --local',
                           'Run moved setup, validation, and test commands with harmless inputs; compare behavior.'],
          'digest' => digest
        }
      end

      def entries
        @changes.flat_map { |change| [change.fetch(:from), change.fetch(:to)] }.uniq.sort
      end

      def desired_states(original = original_states)
        states = original.dup
        @changes.each do |change|
          states[change[:to]] = change.fetch(:after)
          states[change[:from]] = absent if change[:from] != change[:to]
        end
        states
      end

      def original_states = entries.to_h { |path| [path, snapshot(path)] }

      def fresh?(states, reviewed_digest) = digest_for(states) == reviewed_digest

      def snapshot(relative)
        absolute = File.join(@root, relative)
        stat = File.lstat(absolute)
        return { 'type' => 'symlink', 'target' => File.readlink(absolute) } if stat.symlink?
        return file_state(absolute, stat) if stat.file?

        { 'type' => 'unsupported' }
      rescue Errno::ENOENT, Errno::ENOTDIR
        absent
      end

      def file_state(absolute, stat)
        { 'type' => 'file', 'mode' => stat.mode & 0o7777,
          'data' => [File.binread(absolute)].pack('m0') }
      end

      private

      def absent = { 'type' => 'absent' }

      def status(layout)
        return 'blocked' if @blockers.any?
        return 'already_upgraded' if layout == Configuration::Layout::NEW

        'ready'
      end

      def digest = digest_for(original_states)

      def digest_for(states)
        payload = @changes.map do |change|
          [change[:from], change[:to], states.fetch(change[:from]), states.fetch(change[:to]), change[:after]]
        end
        references = @references.sort_by { |item| JSON.generate(item) }
        Digest::SHA256.hexdigest(JSON.generate([payload.sort_by(&:first), @blockers.sort, references]))
      end

      def preflight_directories
        [PATHS::DIRECTORY, PATHS::COMMAND_DIRECTORY, File.dirname(PATHS::NEW_CONTRACT),
         PATHS::NEW_COMMAND_DIRECTORY].each do |relative|
          path = File.join(@root, relative)
          next unless File.exist?(path) || File.symlink?(path)

          @blockers << "#{relative}: expected a real directory" if File.symlink?(path) || !File.directory?(path)
        end
      end
    end
  end
end
