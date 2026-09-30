# frozen_string_literal: true

require 'fileutils'

module Shaka
  module Install
    # Protects an installation path from replacement through a writable ancestor.
    module DirectorySafety
      private

      def ensure_safe_directory(path, label)
        unless File.exist?(path) || File.symlink?(path)
          FileUtils.mkdir_p(path, mode: 0o755)
          File.chmod(0o755, path)
        end
        verify_safe_directory(path, label)
      end

      def verify_safe_directory(path, label)
        resolved = resolved_safe_directory(path, label)
        child = nil
        loop do
          entry = checked_directory(resolved, child, label)
          parent = File.dirname(resolved)
          break if parent == resolved

          child = entry
          resolved = parent
        end
      end

      def resolved_safe_directory(path, label)
        raise ArgumentError, "#{label} is unsafe: #{path}" if File.symlink?(path)

        File.realpath(path)
      rescue Errno::ENOENT, Errno::ELOOP
        raise ArgumentError, "#{label} is unsafe: #{path}"
      end

      def checked_directory(path, child, label)
        entry = File.lstat(path)
        raise ArgumentError, "#{label} is unsafe: #{path}" unless trusted_directory?(entry)
        raise ArgumentError, "#{label} is unsafe: #{path}" if child.nil? && entry.mode.anybits?(0o022)
        raise ArgumentError, "#{label} has an unsafe parent: #{path}" if child && unsafe_parent?(entry, child)

        entry
      rescue Errno::ENOENT, Errno::ELOOP
        raise ArgumentError, "#{label} is unsafe: #{path}"
      end

      def unsafe_parent?(entry, child)
        entry.mode.anybits?(0o022) && !(entry.mode.anybits?(0o1000) && trusted_owner?(child))
      end

      def trusted_directory?(entry)
        entry.directory? && trusted_owner?(entry)
      end

      def trusted_owner?(entry)
        [Process.euid, 0].include?(entry.uid)
      end
    end
  end
end
