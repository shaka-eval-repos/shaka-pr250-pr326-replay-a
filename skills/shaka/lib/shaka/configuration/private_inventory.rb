# frozen_string_literal: true

require 'pathname'
require_relative 'paths'
require_relative 'private_path_hops'

module Shaka
  module Configuration
    # Lists every entry without following directory symlinks or changing Git state.
    class PrivateInventory
      DIRECTORY = File.dirname(Paths::NEW_CONTRACT)
      Result = Data.define(:entries, :blockers, :unsafe)

      def self.private_path?(root:, path:)
        return true if path == Paths::DIRECTORY
        return true if path.casecmp?(Paths::DIRECTORY) &&
                       File.identical?(File.join(root, path), File.join(root, Paths::DIRECTORY))

        prefix = path.split('/').first(2).join('/')
        return true if prefix == DIRECTORY

        prefix.casecmp?(DIRECTORY) && File.identical?(File.join(root, prefix), File.join(root, DIRECTORY))
      end

      def initialize(root:, committed:)
        @root = root
        @committed = committed
        @entries = []
        @blockers = []
        @unsafe = false
      end

      def scan
        scan_agents
        Result.new(entries: @entries.freeze, blockers: @blockers.freeze, unsafe: @unsafe)
      end

      private

      def scan_agents
        agents = File.join(@root, Paths::DIRECTORY)
        stat = File.lstat(agents)
        return unsafe!(Paths::DIRECTORY, 'must be a real directory') unless stat.directory?

        scan_private_directory
      rescue Errno::ENOENT
        nil
      rescue SystemCallError => e
        unsafe!(Paths::DIRECTORY, "cannot be inventoried: #{e.class}")
      end

      def scan_private_directory
        directory = File.join(@root, DIRECTORY)
        stat = File.lstat(directory)
        visit(directory)
        return if @unsafe || stat.directory?

        unsafe!(DIRECTORY, 'must be a real directory')
      rescue Errno::ENOENT
        nil
      rescue SystemCallError => e
        unsafe!(DIRECTORY, "cannot be inventoried: #{e.class}")
      end

      def visit(path)
        relative = Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s
        stat = File.lstat(path)
        entry = { path: relative, type: type(stat), mode: stat.mode & 0o777 }
        inspect_entry(path, relative, stat, entry)
        @entries << entry.freeze
        visit_children(path) if stat.directory?
      rescue SystemCallError => e
        unsafe!(relative, "cannot be inventoried: #{e.class}")
      end

      def visit_children(path)
        Dir.children(path).sort.each { |name| visit(File.join(path, name)) }
      end

      def inspect_entry(path, relative, stat, entry)
        if stat.symlink?
          entry[:target] = File.readlink(path)
          if relative == Paths::NEW_CONTRACT
            unsafe!(relative, 'must be a regular file, not a symlink')
          else
            inspect_link(path, relative, entry)
          end
        elsif !stat.directory? && !stat.file?
          unsafe!(relative, 'must be a regular file, directory, or safe file symlink')
        end
      end

      def inspect_link(path, relative, entry)
        target = File.realpath(path)
        return unsafe!(relative, 'must resolve to a regular file inside the worktree') unless
          target.start_with?("#{@root}/") && File.file?(target)

        resolved = Pathname.new(target).relative_path_from(Pathname.new(@root)).to_s
        entry[:resolved_path] = resolved
        inspect_external_links(path, relative)
        return if resolved.start_with?("#{DIRECTORY}/") || @committed.include?(resolved)

        @blockers << "#{relative} targets file #{resolved} outside #{DIRECTORY} without a candidate HEAD commit"
      rescue SystemCallError, PrivatePathHops::EscapedRoot => e
        unsafe!(relative, "has an unsafe symlink path: #{e.class}")
      end

      def inspect_external_links(path, relative)
        PrivatePathHops.uncommitted(root: @root, path:, committed: @committed).each do |link|
          @blockers << "#{relative} traverses symlink #{link} outside #{DIRECTORY} without a candidate HEAD commit"
        end
      end

      def unsafe!(path, detail)
        @blockers << "#{path} #{detail}"
        @unsafe = true
      end

      def type(stat)
        return 'directory' if stat.directory?
        return 'regular' if stat.file?
        return 'symlink' if stat.symlink?

        'special'
      end
    end
  end
end
