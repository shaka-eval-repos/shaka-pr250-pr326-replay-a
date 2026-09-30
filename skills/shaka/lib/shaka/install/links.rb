# frozen_string_literal: true

require 'fileutils'
require_relative 'package'
require_relative 'link_lock'
require_relative 'directory_safety'

module Shaka
  module Install
    # Points agent skill links at the validated managed copy; see install/README.md.
    class Links
      include LinkLock
      include DirectorySafety

      def initialize(skills_dir, managed, source, names)
        @skills_dir = skills_dir
        @managed = managed
        @source = source
        @names = names
      end

      def switch_all(target)
        ensure_safe_directory(@skills_dir, 'Host skills directory')
        with_lock(@skills_dir) do
          preflight(target)
          previous = @names.to_h { |name| [name, old_target(name)] }
          switch_links(target, previous)
        end
      end

      private

      def switch_links(target, previous)
        changed = []
        begin
          @names.each do |name|
            switch_and_record(name, target, changed)
          end
        rescue SystemCallError, IOError => e
          restore_links(changed, previous)
          raise e
        end
      end

      def restore_links(changed, previous)
        changed.reverse_each do |name|
          restore(name, previous[name])
        rescue SystemCallError, IOError => e
          warn "Could not restore #{destination(name)}: #{e.message}"
        end
      end

      def destination(name) = File.join(@skills_dir, name)

      def switch_and_record(name, target, changed)
        message = switch_one(name, target)
        changed << name
        puts message
      end

      def old_target(name)
        File.readlink(destination(name)) if File.symlink?(destination(name))
      end

      def preflight(target)
        refuse_omitted_links
        @names.each do |name|
          raise ArgumentError, "Package lacks #{name}" unless File.directory?(File.join(target, 'skills', name))
          next unless File.exist?(destination(name)) || File.symlink?(destination(name))
          next if owned?(name)

          raise ArgumentError, "Refusing existing destination: #{destination(name)}"
        end
      end

      def refuse_omitted_links
        (Package::ALLOWED - @names).each do |name|
          next unless File.symlink?(destination(name))

          target = old_target(name)
          next unless source_target?(name, target) || managed_target?(name, target)

          raise ArgumentError, "Existing Shaka skill #{name} was omitted; unlink its managed link " \
                               'before using a package without it, or repeat its install flag'
        end
      end

      def owned?(name)
        target = old_target(name)
        return false unless target
        return true if source_target?(name, target)

        managed_target?(name, target)
      end

      def source_target?(name, target)
        source_skill = File.join(@source, 'skills', name)
        target == source_skill || File.realpath(File.expand_path(target, @skills_dir)) == File.realpath(source_skill)
      rescue Errno::ENOENT
        false
      end

      def managed_target?(name, target)
        expanded = File.expand_path(target, @skills_dir)
        package = File.dirname(expanded, 2)
        File.dirname(package) == @managed && File.basename(package).match?(Package::ID_PATTERN) &&
          expanded == File.join(package, 'skills', name)
      end

      def switch_one(name, package)
        target = File.join(package, 'skills', name)
        return "Already installed: #{destination(name)}" if old_target(name) == target

        replace_link(name, target, '')
        "Installed: #{destination(name)} -> #{target}"
      end

      def restore(name, previous)
        return File.unlink(destination(name)) unless previous

        replace_link(name, previous, 'restore-')
      end

      def replace_link(name, target, suffix)
        temporary = File.join(@skills_dir, ".#{name}.shaka-#{suffix}#{Process.pid}")
        created = File.symlink(target, temporary).zero?
        File.rename(temporary, destination(name))
      ensure
        File.unlink(temporary) if created && File.symlink?(temporary)
      end
    end
  end
end
