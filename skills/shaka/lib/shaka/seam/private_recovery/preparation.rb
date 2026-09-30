# frozen_string_literal: true

module Shaka
  class Seam
    # Preparation and partial-installation checks for the clone-local recovery copy.
    class PrivateRecovery
      def prepare(files)
        with_storage_lock do
          assert_preparation_safe!
          with_temporary_copy do |copy|
            files.each { |path, content| write_prepared_file(copy, path, content) }
            install_copy(copy, inventory_for(copy))
          end
        end
        report('prepared', [], [])
      end

      def prepared_matches?(files)
        current = File.join(@storage, 'current')
        return false unless File.directory?(current) && !File.symlink?(current)

        expected = expected_files(files)
        return false unless snapshot_matches?(current, expected)

        partial_checkout_matches?(expected)
      end

      private

      def partial_checkout_matches?(expected)
        tree = File.join(@root, PRIVATE_DIRECTORY)
        return true unless File.exist?(tree) || File.symlink?(tree)
        return false if File.symlink?(tree) || !File.directory?(tree)

        safe_inventory
        inventory_for(tree).reject { |entry| entry['type'] == 'directory' }
                           .all? { |entry| matching_installed_file?(tree, entry, expected) }
      end

      def assert_preparation_safe!
        adopted = adoption_paths
        raise Error, "Tracked Shaka configuration: #{adopted.join(', ')}" if adopted.any?
        return unless File.exist?(File.join(@root, PRIVATE_DIRECTORY))

        raise Error, "Private destination already exists: #{PRIVATE_DIRECTORY}"
      end

      def write_prepared_file(copy, path, content)
        relative = path.delete_prefix("#{@root}/#{PRIVATE_DIRECTORY}/")
        raise Error, "Invalid private destination: #{path}" if relative == path || relative.start_with?('../')

        destination = File.join(copy, relative)
        mode = relative.start_with?('bin/') ? 0o755 : 0o644
        FileUtils.mkdir_p(File.dirname(destination))
        File.open(destination, File::WRONLY | File::CREAT | File::EXCL, mode) { |file| file.write(content) }
        File.chmod(mode, destination)
      end

      def expected_files(files)
        files.to_h { |path, content| [path.delete_prefix("#{@root}/#{PRIVATE_DIRECTORY}/"), content] }
      end

      def snapshot_matches?(current, expected)
        entries = inventory_for(current).reject { |entry| entry['type'] == 'directory' }
        return false unless snapshot_entries_match?(entries, expected)

        expected.all? { |relative, content| File.binread(File.join(current, relative)) == content.b }
      end

      def snapshot_entries_match?(entries, expected)
        entries.all? { |entry| entry['type'] == 'regular' } &&
          entries.map { |entry| entry.fetch('path') }.sort == expected.keys.sort
      end

      def matching_installed_file?(tree, entry, expected)
        relative = entry.fetch('path')
        entry['type'] == 'regular' && expected.key?(relative) &&
          File.binread(File.join(tree, relative)) == expected.fetch(relative).b &&
          (entry.fetch('mode') & 0o777) == (relative.start_with?('bin/') ? 0o755 : 0o644)
      end
    end
  end
end
