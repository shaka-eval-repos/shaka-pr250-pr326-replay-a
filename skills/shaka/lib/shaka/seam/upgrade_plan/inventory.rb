# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Inventory and move planning for legacy configuration entries.
      module Inventory
        private

        def inventory(layout)
          return inventory_new if layout == Configuration::Layout::NEW
          return inventory_missing unless layout == Configuration::Layout::LEGACY

          inventory_legacy
        rescue Shaka::Error => e
          @blockers << e.message
        end

        def inventory_new
          remaining = legacy_sources.reject { |path| snapshot(path)['type'] == 'absent' }
          if remaining.empty?
            Configuration.worktree(root: @root)
            return
          end

          @blockers << "Legacy entries remain: #{remaining.join(', ')}; resolve the partial migration"
        end

        def inventory_missing
          @blockers << 'No legacy Shaka configuration found; repair the partial migration before retrying'
        end

        def inventory_legacy
          Configuration.worktree(root: @root)
          mapping = move_mapping
          mapping.each { |old, target| add_move(old, target, mapping) }
        end

        def legacy_sources
          [PATHS::CONTRACT, PATHS::REPOSITORY_ALLOWLIST, *PATHS::REQUIRED_COMMANDS.values,
           *PATHS::OPTIONAL_COMMANDS.values, *PATHS::LEGACY_OPTIONAL_COMMANDS.values]
        end

        def move_mapping
          mapping = { PATHS::CONTRACT => PATHS::NEW_CONTRACT }
          if snapshot(PATHS::REPOSITORY_ALLOWLIST)['type'] != 'absent'
            mapping[PATHS::REPOSITORY_ALLOWLIST] = PATHS::NEW_REPOSITORY_ALLOWLIST
          end
          command_paths.each do |path|
            next if snapshot(path)['type'] == 'absent'

            mapping[path] = path.sub(PATHS::COMMAND_DIRECTORY, PATHS::NEW_COMMAND_DIRECTORY)
          end
          mapping
        end

        def command_paths
          PATHS::REQUIRED_COMMANDS.values + PATHS::OPTIONAL_COMMANDS.values + PATHS::LEGACY_OPTIONAL_COMMANDS.values
        end

        def add_move(old, target, mapping)
          source = snapshot(old)
          destination = snapshot(target)
          return unless valid_move?(old, target, source, destination)

          after = move_state(old, target, source, mapping)
          return unless after

          @moves << { 'from' => old, 'to' => target, 'type' => source['type'] }
          @changes << { from: old, to: target, after: after }
        end

        def valid_move?(old, target, source, destination)
          valid_source = %w[file symlink].include?(source['type'])
          @blockers << "#{old}: source must be a regular file or safe symlink" unless valid_source
          valid_destination = destination['type'] == 'absent'
          @blockers << "#{target}: destination already exists; choose its authority manually" unless valid_destination
          valid_source && valid_destination
        end

        def move_state(old, target, source, mapping)
          return relocated_link(old, target, mapping) if source['type'] == 'symlink'

          repaired_file(old, target, source)
        end

        def relocated_link(old, target, mapping)
          source = File.join(@root, old)
          resolved = File.realpath(source)
          return unsafe_link(old) unless resolved.start_with?("#{@root}/")
          return unsafe_link_target(old) if unsafe_link_dependency?(old, resolved, mapping)

          relative = relocated_link_target(source, target, mapping)
          return unsafe_link(old) unless relative

          record_link(old, target, source, relative)
          { 'type' => 'symlink', 'target' => relative }
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
          broken_link(old)
        end

        def broken_link(old)
          @blockers << "#{old}: broken or looping symlink; repair it before upgrading"
          nil
        end

        def unsafe_link(old)
          @blockers << "#{old}: symlink leaves the checkout; replace it before upgrading"
          nil
        end

        def unsafe_link_target(old)
          @blockers << "#{old}: symlink target has unsupported or invocation-relative " \
                       'behavior; repair it before upgrading'
          nil
        end

        def target_depends_on_invocation?(resolved, mapping)
          relative = resolved.delete_prefix("#{@root}/")
          return false if mapping.key?(relative) || !File.file?(resolved)

          text = File.binread(resolved).force_encoding(Encoding::UTF_8)
          return true unless text.valid_encoding? && supported_language?(text)

          invocation_relative?(text) || old_path?(text)
        end

        def record_link(old, target, source, relative)
          @links << { 'from' => old, 'to' => target, 'old_target' => File.readlink(source),
                      'new_target' => relative, 'conversion' => 'retained as a relative link' }
        end
      end
    end
  end
end
