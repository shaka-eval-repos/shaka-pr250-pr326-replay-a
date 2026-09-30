# frozen_string_literal: true

require 'open3'

module Shaka
  module Install
    # Distinguishes a non-Git source from a checkout whose Git inspection failed.
    module GitIgnore
      private

      def ignored_files(root, paths)
        return [] unless root == @source_root

        top = git_root(root)
        return [] unless top
        return [] if paths.empty?

        output = git_ignored(root, paths)
        ignored = output.split("\0").map { |path| File.join(root, path) }
        reject_nested_ignored(top, root, ignored)
        ignored
      end

      def reject_nested_ignored(top, root, ignored)
        return if top == root || ignored.empty?

        raise ArgumentError, 'Nested source has ignored skill files; use a standalone checkout'
      end

      def git_root(root)
        top, status = Open3.capture2('git', '-C', root, 'rev-parse', '--show-toplevel', err: File::NULL)
        return top.strip if status.success?
        return unless git_marker?(root)

        raise ArgumentError, 'Cannot verify Git source checkout'
      rescue Errno::ENOENT
        raise ArgumentError, 'Git is required to verify source skill files'
      end

      def git_marker?(root)
        path = root
        loop do
          return true if File.exist?(File.join(path, '.git')) || File.symlink?(File.join(path, '.git'))
          return false if File.dirname(path) == path

          path = File.dirname(path)
        end
      end

      def git_ignored(root, files)
        relative = files.map { |path| path.delete_prefix("#{root}/") }
        output, status = Open3.capture2('git', '-C', root, 'check-ignore', '-z', '--stdin',
                                        stdin_data: "#{relative.join("\0")}\0", err: File::NULL)
        raise ArgumentError, 'Cannot verify ignored skill files' unless [0, 1].include?(status.exitstatus)

        output
      end
    end
  end
end
