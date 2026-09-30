# frozen_string_literal: true

module Shaka
  class Seam
    class Upgrader
      # Filesystem operations for the layout upgrade.
      module Filesystem
        private

        def existing_parent(path)
          parent = File.dirname(path)
          parent = File.dirname(parent) until File.exist?(parent) || File.symlink?(parent)
          raise Error, "Unsafe parent directory: #{parent}" if File.symlink?(parent) || !File.directory?(parent)

          reject_symlink_parents!(path.delete_prefix("#{@root}/").split('/'))

          parent
        end

        def write_journal(journal)
          tmp = "#{journal_path}.tmp"
          raise Error, "Existing upgrade journal temporary file: #{tmp}" if File.exist?(tmp) || File.symlink?(tmp)

          created = false
          create_journal_temp(tmp, journal)
          created = true
          File.link(tmp, journal_path)
          fsync_journal_directory
          File.delete(tmp)
        ensure
          File.delete(tmp) if created && File.file?(tmp)
        end

        def fsync_journal_directory
          File.open(File.dirname(journal_path), File::RDONLY, &:fsync)
        end

        def create_journal_temp(tmp, journal)
          created = false
          File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            created = true
            file.write(JSON.generate(journal))
            file.flush
            file.fsync
          end
        rescue StandardError
          File.delete(tmp) if created && File.file?(tmp)
          raise
        end

        def write_desired(journal)
          original = journal.fetch('original')
          desired = journal.fetch('desired')
          # Create destinations before removing sources, so an interruption never loses a source.
          created = desired.keys.select { |path| original.fetch(path)['type'] == 'absent' }
          created.sort.each { |path| write_new_state(path, desired.fetch(path)) }
          write_paths(desired.keys - created, desired, original)
        end

        def write_new_state(relative, state)
          absolute = File.join(@root, relative)
          FileUtils.mkdir_p(File.dirname(absolute))
          return File.symlink(state.fetch('target'), absolute) if state.fetch('type') == 'symlink'

          tmp = "#{absolute}.shaka-upgrade-tmp"
          write_temp_file(tmp, state)
          File.link(tmp, absolute)
          File.delete(tmp)
        end

        def write_paths(paths, desired, original)
          paths.sort.each do |path|
            current = UpgradePlan.new(@root).snapshot(path)
            raise Error, "#{path} changed during apply; recovery needed" unless current == original.fetch(path)

            write_state(path, desired.fetch(path))
          end
        end

        def write_state(relative, state)
          absolute = File.join(@root, relative)
          return remove_state(absolute) if state.fetch('type') == 'absent'

          FileUtils.mkdir_p(File.dirname(absolute))
          tmp = "#{absolute}.shaka-upgrade-tmp"
          raise Error, "Existing temporary file: #{tmp}" if File.exist?(tmp) || File.symlink?(tmp)

          write_temporary(tmp, state, relative)
          File.rename(tmp, absolute)
        end

        def write_temporary(tmp, state, relative)
          case state.fetch('type')
          when 'file' then write_temp_file(tmp, state)
          when 'symlink' then File.symlink(state.fetch('target'), tmp)
          else
            raise Error, "Unsupported state for #{relative}"
          end
        end

        def remove_state(absolute)
          File.delete(absolute) if File.exist?(absolute) || File.symlink?(absolute)
        end

        def write_temp_file(tmp, state)
          created = false
          File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            created = true
            write_temp_contents(file, state)
          end
        rescue StandardError
          File.delete(tmp) if created && File.file?(tmp)
          raise
        end

        def write_temp_contents(file, state)
          file.write(state.fetch('data').unpack1('m0'))
          file.chmod(state.fetch('mode'))
          file.flush
          file.fsync
        end

        def cleanup_empty_directories(journal)
          journal.fetch('created_directories').sort_by { |relative| -relative.count('/') }.each do |relative|
            path = File.join(@root, relative)
            Dir.rmdir(path) if File.directory?(path) && !File.symlink?(path) && Dir.empty?(path)
          end
        end
      end
    end
  end
end
