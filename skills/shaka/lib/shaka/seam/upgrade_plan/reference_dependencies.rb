# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # References whose behavior depends on the old command directory.
      module ReferenceDependencies
        private

        def reference_text(path, stat)
          absolute = File.join(@root, path)
          return unless inspect_reference_file?(path, stat, absolute) || contains_layout_reference?(absolute)

          text = File.binread(absolute).force_encoding(Encoding::UTF_8)
          unless text.valid_encoding? && !text.include?("\0")
            raise Error, "#{path}: undecodable old-layout reference; repair it explicitly"
          end

          text
        end

        def dirty_overlap
          planned = entries
          return if planned.empty?

          specs = planned.map { |path| ":(literal)#{path}" }
          checkout_edits = git_paths('diff', '--name-only', '-z', 'HEAD', '--', *specs) +
                           git_paths('ls-files', '--others', '--exclude-standard', '-z', '--', *specs) +
                           git_paths('ls-files', '--others', '--ignored', '--exclude-standard', '-z', '--', *specs)
          checkout_edits.intersection(planned).each do |path|
            @blockers << "#{path}: overlapping checkout edit; save or repair it before upgrading"
          end
        end

        def git_paths(*)
          output, error, status = Open3.capture3('git', '-C', @root, *)
          raise Error, "Cannot inspect checkout edits: #{error.strip}" unless status.success?

          output.split("\0")
        end

        def contains_layout_reference?(absolute)
          carry = ''.b
          File.open(absolute, 'rb') do |file|
            while (chunk = file.read(65_536))
              normalized = normalize_shell_fragments(carry + chunk)
              return true if normalized.include?(PATHS::DIRECTORY.b)
              return false if chunk.include?("\0")

              carry = reference_carry(normalized, PATHS::DIRECTORY.b)
            end
          end
          false
        end

        def reference_carry(normalized, needle)
          size = [normalized.bytesize, needle.bytesize + 3].min
          normalized.byteslice(-size, size)
        end

        def scan_moved_config_reference(path)
          return if path.start_with?("#{PATHS::COMMAND_DIRECTORY}/")

          state = snapshot(path)
          return unless state['type'] == 'file'

          text = state.fetch('data').unpack1('m0').force_encoding(Encoding::UTF_8)
          return unless text.valid_encoding?
          return unless old_path?(text)

          @references << { 'path' => path, 'kind' => 'moved configuration', 'paths' => matching_paths(text) }
          @blockers << "#{path}: old layout reference in moved configuration; repair it explicitly"
        end

        def direct_link_target(source)
          File.expand_path(File.readlink(source), File.dirname(source))
        end

        def relocated_link_target(source, target, mapping)
          direct = direct_link_target(source)
          return unless direct.start_with?("#{@root}/")

          link_target(direct, target, mapping)
        end

        def link_target(direct, target, mapping)
          original = direct.delete_prefix("#{@root}/")
          destination = mapping.fetch(original, original)
          Pathname.new(File.join(@root, destination)).relative_path_from(
            Pathname.new(File.dirname(File.join(@root, target)))
          ).to_s
        end

        def scan_symlink_reference(path)
          resolved = File.realpath(File.join(@root, path))
          return scan_external_symlink_reference(path) unless resolved.start_with?("#{@root}/")

          scan_symlink_target_content(path, resolved)
          targets = symlink_chain_targets(path) + [resolved.delete_prefix("#{@root}/")]
          affected = targets.flat_map { |target| moved_beneath(target) }.uniq
          return if affected.empty?

          @references << { 'path' => path, 'kind' => 'inbound symlink', 'paths' => affected }
          @blockers << "#{path}: symlink targets moved path #{affected.first}; repair the link explicitly"
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
          nil
        end

        def moved_beneath(target)
          @moves.filter_map do |move|
            source = move.fetch('from')
            source if source == target || source.start_with?("#{target}/")
          end
        end

        def scan_unmoved_tool(path, text)
          return unless path.start_with?("#{PATHS::COMMAND_DIRECTORY}/")
          return unless invocation_relative?(text) || relative_command_call?(text)

          @references << { 'path' => path, 'kind' => 'unmoved tool dependency', 'paths' => [] }
          @blockers << "#{path}: tool uses an invocation-relative path; check moved sibling commands explicitly"
        end

        def relative_command_call?(text)
          @moves.any? do |move|
            source = move.fetch('from')
            next unless source.start_with?("#{PATHS::COMMAND_DIRECTORY}/")

            text.match?(%r{(?<![[:alnum:]_./-])\./#{Regexp.escape(File.basename(source))}(?![[:alnum:]_./-])})
          end
        end
      end
    end
  end
end
