# frozen_string_literal: true

require 'digest'
require 'fileutils'
require_relative 'checkout_reference'
require_relative 'git_ignore'

module Shaka
  module Install
    # Enumerates and hashes only regular package files and directories.
    class Tree
      include CheckoutReference
      include GitIgnore

      def initialize(names, source_root: nil, source_alias: nil)
        @names = names
        @source_root = source_root
        @source_alias = source_alias
      end

      def entries(root, name)
        skill = File.join(root, 'skills', name)
        raise ArgumentError, "Missing skill: #{skill}" unless File.directory?(skill) && !File.symlink?(skill)

        validate_skill_entry_points(skill, name)

        paths = Dir.glob('**/*', File::FNM_DOTMATCH, base: skill)
                   .grep_v(/\A\.{1,2}\z/)
                   .sort.map { |path| File.join(skill, path) }
        ignored = ignored_files(root, paths)
        paths.reject { |path| ignored_path?(path, ignored) }
      end

      def hash(root, names = @names, normalized: false)
        digest = Digest::SHA256.new
        names.each do |name|
          digest.update(name).update("\0")
          paths = entries(root, name)
          add(digest, File.join(root, 'skills', name), root, normalized: normalized)
          paths.each { |path| add(digest, path, root, normalized: normalized) }
        end
        digest.hexdigest
      end

      def copy(source, target)
        @names.each do |name|
          destination = File.join(target, 'skills', name)
          FileUtils.mkdir_p(destination)
          directories = [[destination, safe_mode(File.stat(File.join(source, 'skills', name)).mode)]]
          entries(source, name).each do |path|
            copy_entry(path, source, target, directories)
          end
          directories.reverse_each { |path, mode| File.chmod(mode, path) }
        end
        File.chmod(0o755, File.join(target, 'skills'))
      end

      def reject_checkout_references(root, source)
        checkouts = [source, @source_alias].compact.uniq.map(&:b)
        @names.each do |name|
          entries(root, name).select { |path| File.file?(path) }.each do |path|
            content = File.binread(path)
            raise ArgumentError, "Checkout reference in package: #{path}" if references_checkout?(content, checkouts)
          end
        end
      end

      private

      def ignored_path?(path, ignored) = ignored.any? { |entry| path == entry || path.start_with?("#{entry}/") }

      def validate_skill_entry_points(skill, name)
        required = name == 'shaka' ? %w[SKILL.md scripts/shaka] : ['SKILL.md']
        required.each do |entry|
          path = File.join(skill, entry)
          raise ArgumentError, "Missing skill entry point: #{path}" unless File.file?(path)
        end
        return unless name == 'shaka'

        helper = File.join(skill, 'scripts/shaka')
        raise ArgumentError, "Skill helper is not executable: #{helper}" unless File.stat(helper).mode.anybits?(0o100)
      end

      def copy_entry(path, source, target, directories)
        destination = File.join(target, path.delete_prefix("#{source}/"))
        validate_entry(path)
        if File.directory?(path)
          FileUtils.mkdir_p(destination)
          directories << [destination, safe_mode(File.stat(path).mode)]
        else
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.cp(path, destination)
          File.chmod(safe_mode(File.stat(path).mode), destination)
        end
      end

      def add(digest, path, root, normalized: false)
        validate_entry(path)
        add_field(digest, path.delete_prefix("#{root}/"))
        mode = File.stat(path).mode & 0o777
        add_field(digest, (normalized ? safe_mode(mode) : mode).to_s)
        add_field(digest, File.file?(path) ? 'file' : 'directory')
        add_field(digest, File.file?(path) ? File.binread(path) : '')
      end

      def add_field(digest, value)
        digest.update("#{value.bytesize}:").update(value)
      end

      def safe_mode(mode) = mode & 0o755

      def validate_entry(path)
        raise ArgumentError, "Symlink in skill package: #{path}" if File.symlink?(path)
        raise ArgumentError, "Unsupported package entry: #{path}" unless File.file?(path) || File.directory?(path)

        forbidden = File.directory?(path) ? 0o5000 : 0o7000
        raise ArgumentError, "Special permission bits in skill: #{path}" if File.stat(path).mode.anybits?(forbidden)
      end
    end
  end
end
