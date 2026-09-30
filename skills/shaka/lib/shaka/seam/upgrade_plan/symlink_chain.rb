# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Follows in-checkout link hops for dependency checks.
      module SymlinkChain
        private

        def symlink_chain_targets(path)
          current = File.join(@root, path)
          targets = []
          while File.symlink?(current)
            raise Error, "#{path}: symlink chain cannot be inspected safely" if targets.length >= 40

            current = File.expand_path(File.readlink(current), File.realpath(File.dirname(current)))
            break unless current.start_with?("#{@root}/")

            targets << current.delete_prefix("#{@root}/")
          end
          targets
        end

        def chain_crosses_moved_command?(old, mapping)
          symlink_chain_targets(old).drop(1).any? { |path| mapping.key?(path) }
        end

        def unsafe_link_dependency?(old, resolved, mapping)
          target_depends_on_invocation?(resolved, mapping) || chain_crosses_moved_command?(old, mapping)
        end

        def scan_symlink_target_content(path, resolved)
          relative = resolved.delete_prefix("#{@root}/")
          return if @tracked_reference_paths.key?(relative) || !File.file?(resolved)
          return unless inspect_reference_file?(relative, File.lstat(resolved), resolved) ||
                        contains_layout_reference?(resolved)

          text = File.binread(resolved).force_encoding(Encoding::UTF_8)
          return unless untracked_target_dependency?(relative, text)

          @references << { 'path' => path, 'kind' => 'untracked symlink target', 'paths' => [PATHS::DIRECTORY] }
          @blockers << "#{path}: symlink target contains an old-layout reference; repair it explicitly"
        end

        def untracked_target_dependency?(relative, text)
          !text.valid_encoding? || old_path?(text) || segmented_reference?(text) ||
            relative_helper_dependency?(relative, text)
        end

        def scan_external_symlink_reference(path)
          @references << { 'path' => path, 'kind' => 'external symlink', 'paths' => [] }
          @blockers << "#{path}: external symlink target cannot be verified; repair it explicitly"
        end
      end
    end
  end
end
