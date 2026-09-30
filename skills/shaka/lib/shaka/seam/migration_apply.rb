# frozen_string_literal: true

require 'open3'
require 'yaml'
require_relative 'initializer'
require_relative 'initializer_destination'
require_relative 'initializer_readme'

module Shaka
  class Seam
    # Replaces the predecessor contract with a sibling tempfile, then rename.
    module MigrationApplyWrite
      private

      def persist(path, content, created)
        if contract_replaceable?(path)
          replace_contract(path, content)
          yield
          return
        end
        return if File.file?(path)

        create_pointer(path, content, created)
      end

      def create_pointer(path, content, created)
        Configuration.create_generated_file(root:, path:, content:, mode: destination_mode(path)) { created << path }
      end

      def replace_contract(path, content)
        @contract_mode ||= File.stat(path).mode & 0o777
        Configuration.replace_contract(root:, content:, mode: destination_mode(path))
      end

      def restore_contract
        path = Configuration.path(root, :CONTRACT)
        replace_contract(path, @source)
        File.chmod(@contract_mode, path) if @contract_mode
      end
    end

    # Writes migrate destinations only after every preflight succeeds.
    module MigrationApply
      include InitializerDestination
      include InitializerReadme
      include MigrationApplyWrite

      private

      def apply(report)
        raise Error, "blocking fields: #{report.fetch('blocking').join(', ')}" unless report.fetch('blocking').empty?

        files = generated_files(report)
        preflight_directories
        refuse_new_configuration!
        preflight_migration_files(files)
        created = write_migration_files(files)
        verify_candidate(created)
        CheckReport.emit(report)
      end

      def refuse_new_configuration!
        return unless Configuration::Layout.worktree(root:, allow_missing: true) == Configuration::Layout::NEW

        raise Error, "#{Configuration::Paths::NEW_CONTRACT} already exists; seam migrate writes " \
                     "#{Configuration::Paths::CONTRACT} and cannot create a second configuration"
      end

      def generated_files(report)
        {
          Configuration.path(root, :CONTRACT) => contract_source(report.fetch('established')),
          Configuration.path(root, :POINTER) => readme_source
        }
      end

      def contract_source(established)
        Configuration.generated_contract(marker: Migrator::MARKER, data: typed_contract(established))
      end

      def typed_contract(established)
        {
          'version' => 1,
          'base_branch' => established['base_branch'],
          'review' => established.fetch('review'),
          'merge' => established.fetch('merge'),
          'branches' => established['branches'],
          'wip' => established['wip'],
          'repo_prefix' => established['repo_prefix']
        }.compact
      end

      def preflight_migration_files(files)
        files.each do |path, content|
          next unless File.exist?(path) || File.symlink?(path)
          next if contract_replaceable?(path)
          next if matching_destination?(path, content)

          raise Error, "Refusing existing destination: #{path.delete_prefix("#{root}/")}"
        end
      end

      def contract_replaceable?(path)
        path == Configuration.path(root, :CONTRACT) && Configuration.contract_matches?(root, @source)
      end

      def write_migration_files(files)
        created = []
        replaced = false
        files.each { |path, content| persist(path, content, created) { replaced = true } }
        created
      rescue StandardError
        rollback_created(created)
        restore_contract if replaced
        raise
      end

      def verify_candidate(created)
        output, error, status = Open3.capture3(shaka_command, 'seam', 'check', '--root', root, '--local')
        return if status.success?

        undo_apply(created)
        detail = error.strip.empty? ? output.strip : error.strip
        raise Error, "candidate seam check failed: #{detail}"
      end

      def undo_apply(created)
        rollback_created(created)
        restore_contract if contract_changed?
      end

      def contract_changed?
        Configuration.contract_changed?(root, @source)
      end

      def shaka_command = File.expand_path('../../../scripts/shaka', __dir__)

      def generated_by = 'shaka seam migrate'

      def rollback_created(created)
        created.each { |path| File.delete(path) if File.file?(path) }
      end
    end
  end
end
