# frozen_string_literal: true

module Shaka
  class Seam
    class Upgrader
      # Recovery operations for the layout upgrade.
      module Recovery
        private

        def recover
          journal = load_journal
          validate_journal!(journal)

          return finish_completed_upgrade(journal) if completed_upgrade?(journal)

          restore(journal)
          puts JSON.generate('mode' => 'recover', 'status' => 'restored',
                             'paths' => journal.fetch('original').keys.sort)
          0
        end

        def load_journal
          unless File.file?(journal_path) && !File.symlink?(journal_path)
            raise Error, "No regular interrupted upgrade journal at #{journal_path}"
          end

          JSON.parse(File.read(journal_path))
        end

        def restore(journal)
          original = journal.fetch('original')
          verify_recovery_state!(journal)
          journal.fetch('temporary').each { |relative| remove_state(File.join(@root, relative)) }
          original.sort.each { |path, state| write_state(path, state) }
          cleanup_empty_directories(journal)
          cleanup_owned_journal_temp
          File.delete(journal_path)
        end

        def verify_recovery_state!(journal)
          journal.fetch('original').each do |path, before|
            current = UpgradePlan.new(@root).snapshot(path)
            next if current == before || current == journal.fetch('desired').fetch(path)

            raise Error, "#{path} changed after interruption; preserve that edit and repair manually"
          end
          verify_temporary_states!(journal)
        end

        def validate_journal!(journal)
          validate_journal_version!(journal)
          original, desired = journal_states!(journal)
          raise Error, 'Upgrade journal path sets differ' unless original.keys.sort == desired.keys.sort

          original.each_key { |path| validate_journal_entry!(path, original[path], desired[path]) }
          validate_temporary_paths!(journal, original.keys)
          validate_created_directories!(journal)
        end

        def validate_journal_version!(journal)
          valid = journal.is_a?(Hash) && journal['version'] == 1
          raise Error, "Unsupported upgrade journal at #{journal_path}" unless valid
        end

        def journal_states!(journal)
          original, desired = journal.values_at('original', 'desired')
          valid = original.is_a?(Hash) && desired.is_a?(Hash)
          raise Error, 'Upgrade journal must contain original and desired states' unless valid

          [original, desired]
        end

        def validate_journal_entry!(path, before, after)
          raise Error, 'Upgrade journal paths must be text' unless path.is_a?(String)

          safe_recovery_path!(path)
          validate_journal_state!(before)
          validate_journal_state!(after)
        end

        def validate_journal_state!(state)
          raise Error, 'Invalid upgrade journal state' unless state.is_a?(Hash)

          valid = case state['type']
                  when 'absent' then true
                  when 'symlink' then state['target'].is_a?(String)
                  when 'file' then valid_file_state?(state)
                  else false
                  end
          raise Error, 'Invalid upgrade journal state' unless valid
        end

        def valid_file_state?(state)
          return false unless state['mode'].is_a?(Integer) && state['mode'].between?(0, 0o7777)
          return false unless state['data'].is_a?(String)

          state['data'].unpack1('m0')
          true
        rescue ArgumentError
          false
        end

        def validate_temporary_paths!(journal, paths)
          expected_temps = paths.map { |path| "#{path}.shaka-upgrade-tmp" }.sort
          temporary = journal['temporary']
          valid = temporary.is_a?(Array) && temporary.all?(String) && temporary.sort == expected_temps
          raise Error, 'Upgrade journal temporary paths differ' unless valid
        end

        def safe_recovery_path!(relative)
          absolute = File.expand_path(relative, @root)
          parts = relative.split('/')
          unsafe = relative.start_with?('/') || parts.include?('..') || parts.include?('.git') ||
                   !absolute.start_with?("#{@root}/")
          raise Error, "Unsafe upgrade journal path: #{relative}" if unsafe

          reject_symlink_parents!(parts)
          existing_parent(absolute)
        end

        def reject_symlink_parents!(parts)
          path = @root
          parts[0...-1].each do |part|
            path = File.join(path, part)
            raise Error, "Unsafe symlink parent in upgrade journal: #{path}" if File.symlink?(path)
          end
        end
      end
    end
  end
end
