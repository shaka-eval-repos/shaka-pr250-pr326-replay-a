# frozen_string_literal: true

require 'pathname'
require_relative 'paths'

module Shaka
  module Configuration
    # Finds uncommitted symlinks traversed by a candidate worktree path.
    class PrivatePathHops
      MAX_LINKS = 40
      DIRECTORY = File.dirname(Paths::NEW_CONTRACT)
      class EscapedRoot < StandardError; end

      def self.uncommitted(root:, path:, committed:)
        new(root:, path:, committed:).uncommitted
      end

      def self.committed_path?(root:, path:, committed:)
        resolved = Pathname.new(File.realpath(File.expand_path(path, root))).relative_path_from(Pathname.new(root)).to_s
        (resolved.start_with?("#{DIRECTORY}/") || committed.include?(resolved)) &&
          uncommitted(root:, path:, committed:).empty?
      rescue SystemCallError, EscapedRoot
        false
      end

      def initialize(root:, path:, committed:)
        @root = root
        @path = path
        @committed = committed
        @pending = components(File.expand_path(path, root))
        @resolved = []
        @missing = []
        @hops = 0
      end

      def uncommitted
        consume(@pending.shift) until @pending.empty?
        @missing
      end

      private

      def components(path)
        prefix = "#{@root}/"
        raise EscapedRoot, path unless path.start_with?(prefix)

        path.delete_prefix(prefix).split('/')
      end

      def consume(part)
        return if part == '.' || part.empty?
        return ascend if part == '..'

        candidate = File.join(@root, *@resolved, part)
        return @resolved << part unless File.symlink?(candidate)

        follow(candidate)
      end

      def ascend
        raise EscapedRoot, @path if @resolved.empty?

        @resolved.pop
      end

      def follow(candidate)
        relative = Pathname.new(candidate).relative_path_from(Pathname.new(@root)).to_s
        @missing << relative unless relative.start_with?("#{DIRECTORY}/") ||
                                    @committed.include?(relative)
        @hops += 1
        raise Errno::ELOOP, candidate if @hops > MAX_LINKS

        follow_target(File.readlink(candidate))
      end

      def follow_target(target)
        if Pathname.new(target).absolute?
          @pending.unshift(*components(target))
          @resolved.clear
        else
          @pending.unshift(*target.split('/'))
        end
      end
    end
  end
end
