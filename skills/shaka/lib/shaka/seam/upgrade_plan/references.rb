# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Tracked reference inventory and checkout overlap checks.
      module References
        private

        def scan_references
          moved = @moves.map { |item| item.fetch('from') }
          moved.each { |path| scan_moved_config_reference(path) }
          @tracked_reference_paths = tracked_paths.to_h { |path| [path, true] }
          @tracked_reference_paths.each_key { |path| scan_reference(path) unless moved.include?(path) }
        end

        def tracked_paths
          output, error, status = Open3.capture3('git', '-C', @root, 'ls-files', '-z')
          raise Error, "Cannot inventory tracked references: #{error.strip}" unless status.success?

          output.split("\0").sort
        end

        def scan_reference(path)
          stat = File.lstat(File.join(@root, path))
          return scan_symlink_reference(path) if stat.symlink?
          return unless stat.file?

          scan_regular_reference(path, stat)
        rescue Errno::ENOENT, Errno::ENOTDIR
          @blockers << "#{path}: tracked file is absent; materialize or restore it before upgrading"
        rescue Error => e
          @blockers << e.message
        end

        def scan_regular_reference(path, stat)
          text = reference_text(path, stat)
          return unless text

          scan_relative_helper_dependency(path, text)
          scan_unmoved_tool(path, text)
          scan_complex_references(path, text)
          return unless text.include?("#{PATHS::DIRECTORY}/")

          executable = text.start_with?('#!') || stat.mode & 0o111 != 0
          updated = text.lines.map { |line| rewrite_line(path, line, executable) }.join
          return if updated == text

          @changes << { from: path, to: path, after: file_state_from_text(stat, updated) }
        end

        def file_state_from_text(stat, text)
          { 'type' => 'file', 'mode' => stat.mode & 0o7777, 'data' => [text.b].pack('m0') }
        end

        def rewrite_line(path, line, executable)
          keys = matching_paths(line)
          return line if keys.empty? && !directory_reference?(line)

          record_reference(path, line, keys)
          return historical_reference(path, line) if historical_line?(path, line)
          return block_directory_reference(path, line) if directory_reference?(line)
          return block_reference(path, keys, executable, line) if blocked_reference?(keys, executable, line)

          replace_paths(line, keys)
        end

        def record_reference(path, line, keys)
          paths = keys.dup
          paths << PATHS::COMMAND_DIRECTORY if command_directory_reference?(line)
          paths << PATHS::DIRECTORY if layout_glob_reference?(line)
          paths << PATHS::DIRECTORY if normalized_internal_reference?(line)
          kind = reference_kind(path, historical_line?(path, line))
          @references << { 'path' => path, 'kind' => kind, 'paths' => paths }
        end

        def replace_paths(line, keys)
          keys.reduce(line) do |result, old|
            result.gsub(token_pattern(old)) { "#{::Regexp.last_match[:lead]}#{reference_mapping.fetch(old)}" }
          end
        end

        def historical_reference(path, line)
          return line if File.basename(path).match?(/\A(?:CHANGELOG|HISTORY|RELEASE[-_]?NOTES)(?:\.|\z)/i)

          @blockers << "#{path}: historical guide old-path reference; repair it explicitly"
          line
        end

        def block_directory_reference(path, line)
          reason = if command_directory_reference?(line)
                     'old command-directory reference'
                   elsif normalized_internal_reference?(line)
                     'normalized old-layout reference'
                   else
                     'old layout-directory pattern'
                   end
          @blockers << "#{path}: #{reason} needs explicit repair"
          line
        end

        def reference_kind(path, historical)
          return 'historical' if historical
          return 'tracked CI' if path.start_with?('.github/')

          'repository guidance or executable reference'
        end

        def blocked_reference?(keys, executable, line)
          executable || keys.any? { |old| @moves.none? { |move| move['from'] == old } } ||
            keys.any? { |old| dynamic_reference?(line, old) || complex_reference?(line, old) }
        end

        def block_reference(path, keys, executable, line)
          reason = if executable
                     'executable old-path reference'
                   elsif keys.any? { |old| dynamic_reference?(line, old) || complex_reference?(line, old) }
                     "dynamic old-path reference #{keys.join(', ')}"
                   else
                     "reference to unmoved path #{keys.join(', ')}"
                   end
          @blockers << "#{path}: #{reason} needs explicit repair"
          line
        end
      end
    end
  end
end
