# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Detects old paths hidden by unstaged edits to tracked files.
      module IndexedReferences
        private

        def scan_indexed_reference_edits
          scan_hidden_index_flags
          edited = git_paths('diff', '--name-only', '-z', '--')
          return if edited.empty?

          scan_indexed_literal_references(edited)
          edited.each { |path| scan_indexed_segmented_reference(path) }
        end

        def scan_hidden_index_flags
          git_paths('ls-files', '-v', '-z').each do |record|
            tag = record[0]
            next unless %w[h S s].include?(tag)

            path = record[2..]
            @blockers << "#{path}: index flag hides checkout edits; clear assume-unchanged or skip-worktree"
          end
        end

        def scan_indexed_literal_references(edited)
          output, error, status = Open3.capture3('git', '-C', @root, 'grep', '--cached', '-l', '-z', '-F',
                                                 "#{PATHS::DIRECTORY}/", '--')
          raise Error, "Cannot inspect indexed references: #{error.strip}" unless [0, 1].include?(status.exitstatus)

          edited.intersection(output.split("\0")).each do |path|
            @blockers << "#{path}: indexed old-layout reference differs from worktree; reconcile it before upgrading"
          end
        end

        def scan_indexed_segmented_reference(path)
          indexed = indexed_blob(path).force_encoding(Encoding::UTF_8)
          unless indexed.valid_encoding?
            scan_undecodable_indexed_reference(path, indexed)
            return
          end
          return unless indexed_complex_reference?(path, indexed)

          @blockers << "#{path}: indexed segmented old-layout reference differs from worktree; " \
                       'reconcile it before upgrading'
        end

        def indexed_complex_reference?(path, text)
          segmented_reference?(text) || continued_old_path?(text) || alias_reference?(text) ||
            shell_fragmented_reference?(text) || unsupported_path_reference?(text) ||
            relative_helper_dependency?(path, text)
        end

        def scan_undecodable_indexed_reference(path, indexed)
          normalized = indexed.b.gsub(/\\\r?\n/, '')
          return unless normalized.include?(PATHS::DIRECTORY.b)

          @blockers << "#{path}: undecodable indexed old-layout reference differs from worktree; " \
                       'reconcile it before upgrading'
        end

        def indexed_blob(path)
          output, error, status = Open3.capture3('git', '-C', @root, 'show', ":#{path}")
          return output if status.success?

          raise Error, "Cannot inspect indexed reference #{path}: #{error.strip}"
        end
      end
    end
  end
end
