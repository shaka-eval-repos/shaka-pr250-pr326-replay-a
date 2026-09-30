# frozen_string_literal: true

module Shaka
  class Seam
    class Upgrader
      # Validates recoverable temporary files and newly created layout directories.
      module RecoveryChecks
        private

        def validate_created_directories!(journal)
          actual = journal['created_directories']
          allowed = [Configuration::Paths::NEW_COMMAND_DIRECTORY, File.dirname(Configuration::Paths::NEW_CONTRACT)]
          return if actual.is_a?(Array) && actual.all?(String) && actual.uniq == actual && (actual - allowed).empty?

          raise Error, 'Upgrade journal created directories are invalid'
        end

        def verify_temporary_states!(journal)
          journal.fetch('temporary').each do |temporary|
            path = temporary.delete_suffix('.shaka-upgrade-tmp')
            current = UpgradePlan.new(@root).snapshot(temporary)
            allowed = [{ 'type' => 'absent' }, journal.fetch('original').fetch(path),
                       journal.fetch('desired').fetch(path)]
            next if allowed.include?(current)

            raise Error, "#{temporary} changed after interruption; preserve that edit and repair manually"
          end
        end

        def cleanup_owned_journal_temp
          temporary = "#{journal_path}.tmp"
          journal_state = File.lstat(journal_path)
          temporary_state = File.lstat(temporary)
          return unless temporary_state.file? && journal_state.dev == temporary_state.dev &&
                        journal_state.ino == temporary_state.ino

          File.delete(temporary)
        rescue Errno::ENOENT
          nil
        end
      end
    end
  end
end
