# frozen_string_literal: true

module Shaka
  class Seam
    # Separate inspection restore and bounded copy rotation.
    class PrivateRecovery
      def restore(to:, id: nil, previous: false)
        target = inspection_target(to)
        directory = validated_storage(id)
        with_storage_lock(storage: directory, create: false) do
          source = recovery_source(id, previous)
          FileUtils.mkdir_p(File.dirname(target))
          copy_tree(source, target)
          { 'status' => 'restored_for_comparison', 'path' => target, 'source' => source }
        end
      end

      private

      def inspection_target(to)
        target = File.expand_path(to)
        parent = existing_parent(target)
        actual_parent = File.realpath(parent)
        assert_outside_worktrees!(target, actual_parent)
        raise Error, "Inspection destination already exists: #{to}" if File.exist?(target) || File.symlink?(target)

        target
      end

      def assert_outside_worktrees!(target, parent)
        forbidden = forbidden_roots
        if [target, parent].any? { |path| forbidden.any? { |dir| path == dir || path.start_with?("#{dir}/") } }
          raise Error, 'Restore requires a separate inspection path outside the worktree'
        end
        raise Error, 'Restore requires a path outside every Git worktree' if inside_worktree?(parent)
      end

      def existing_parent(path)
        parent = File.dirname(path)
        parent = File.dirname(parent) until File.exist?(parent)
        parent
      end

      def inside_worktree?(parent)
        _out, _error, status = Configuration::PrivateGitPaths.capture(parent, 'rev-parse', '--show-toplevel')
        status.success?
      end

      def forbidden_roots
        worktrees = git('worktree', 'list', '--porcelain', '-z').split("\0").filter_map do |field|
          next unless field.start_with?('worktree ')

          path = field.delete_prefix('worktree ')
          File.realpath(path) if File.directory?(path)
        end
        [@common_git_dir, *worktrees]
      end

      def recovery_source(id, previous)
        directory = validated_storage(id)
        source = File.join(directory, previous ? 'previous' : 'current')
        source = File.join(directory, 'previous') unless previous || File.exist?(source)
        raise Error, "No recovery copy at #{source}" unless File.directory?(source) && !File.symlink?(source)

        source
      end

      def validated_storage(id)
        return @storage if !id && @storage
        raise Error, 'No recovery copy for this worktree' unless id

        raise Error, 'Invalid recovery identity' unless id.match?(/\A[0-9a-f]{64}\z/)

        File.join(@common_git_dir, DIRECTORY, id)
      end

      def save_from(tree)
        with_temporary_copy do |copy|
          copy_tree(tree, copy)
          install_copy(copy, inventory_for(copy))
        end
      end

      def with_temporary_copy
        FileUtils.mkdir_p(@storage, mode: 0o700)
        copy = File.join(@storage, "pending-#{SecureRandom.hex(8)}")
        FileUtils.mkdir_p(copy, mode: 0o700)
        yield copy
      ensure
        FileUtils.rm_rf(copy) if defined?(copy) && copy && File.exist?(copy)
      end

      def write_manifest(inventory)
        manifest = { 'path' => @root, 'branch' => git('branch', '--show-current').strip,
                     'time' => Time.now.utc.iso8601, 'inventory' => inventory }
        temporary = File.join(@storage, "manifest-#{SecureRandom.hex(6)}")
        File.write(temporary, JSON.pretty_generate(manifest))
        File.rename(temporary, File.join(@storage, 'manifest.json'))
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary) && temporary
      end

      def copy_tree(source, destination)
        FileUtils.mkdir_p(destination, mode: 0o700)
        Dir.children(source).each do |name|
          from = File.join(source, name)
          to = File.join(destination, name)
          copy_entry(from, to)
        end
      end

      def copy_entry(from, to)
        stat = File.lstat(from)
        return copy_directory(from, to, stat) if stat.directory?
        return File.symlink(File.readlink(from), to) if stat.symlink?
        raise Error, "Unsupported recovery entry: #{from}" unless stat.file?

        FileUtils.copy_file(from, to)
        File.chmod(stat.mode & 0o7777, to)
      end

      def copy_directory(from, to, stat)
        copy_tree(from, to)
        File.chmod(stat.mode & 0o7777, to)
      end
    end
  end
end
