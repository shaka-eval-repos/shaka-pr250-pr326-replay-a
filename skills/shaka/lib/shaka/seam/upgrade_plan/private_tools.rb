# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Private old-directory tools may depend on standard commands being moved.
      module PrivateTools
        private

        def scan_reference_inventory
          scan_references
          scan_indexed_reference_edits
          scan_private_old_tools
        end

        def scan_private_old_tools
          directory = "#{PATHS::COMMAND_DIRECTORY}/"
          private_paths = git_paths('ls-files', '--others', '--exclude-standard', '-z', '--', directory) +
                          git_paths('ls-files', '--others', '--ignored', '--exclude-standard', '-z', '--', directory)
          private_paths.uniq.sort.each do |path|
            @blockers << "#{path}: untracked old-directory tool may depend on moved commands; repair it explicitly"
          end
        end
      end
    end
  end
end
