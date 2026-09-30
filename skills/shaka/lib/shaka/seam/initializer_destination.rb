# frozen_string_literal: true

require 'fileutils'
require_relative '../error'
require_relative '../configuration/paths'

module Shaka
  class Seam
    # Refuses foreign destinations and writes generated seam files conservatively.
    module InitializerDestination
      private

      def destination_directories
        [Configuration::Paths::DIRECTORY, File.dirname(Initializer::LAYOUT.contract),
         Initializer::LAYOUT.command_directory]
      end

      def preflight_directories
        destination_directories.each do |relative|
          path = File.join(@root, relative)
          next unless File.exist?(path) || File.symlink?(path)

          raise Error, "Refusing unsafe directory: #{relative}" if File.symlink?(path) || !File.directory?(path)
        end
      end

      def preflight_files(files)
        files.each do |path, content|
          next unless File.exist?(path) || File.symlink?(path)
          next if matching_destination?(path, content)

          raise Error, "Refusing existing destination: #{path.delete_prefix("#{@root}/")}"
        end
      end

      # Refuse before the first write when a destination cannot be created, so a denied
      # approval leaves nothing behind and the same command can simply run again.
      def preflight_permissions(files)
        pending = files.keys.reject { |path| File.file?(path) }
        pending.map { |path| File.dirname(path) }.uniq.each do |directory|
          parent = existing_parent(directory)
          next if File.writable?(parent) && File.executable?(parent)

          raise Error, "Permission denied for #{directory.delete_prefix("#{@root}/")}: " \
                       "#{parent.delete_prefix("#{@root}/")} is not writable; grant write access and rerun seam init"
        end
      end

      def existing_parent(path)
        path = File.dirname(path) until File.exist?(path)
        path
      end

      def matching_destination?(path, content)
        return false unless File.file?(path) && !File.symlink?(path)
        return false unless (File.stat(path).mode & 0o7777) == destination_mode(path)

        existing = Configuration.generated_text(root: @root, path:)
        existing == content || previously_generated_readme?(path, existing)
      end

      # The pointer records the generating skill version, so an upgrade changes its text while
      # the repository's copy stays correct. Recognizing our own marker keeps a plain repeat of
      # `seam init` from aborting over a file nobody edited. Everything else stays byte-exact.
      def previously_generated_readme?(path, existing)
        path == File.join(@root, Initializer::POINTER_PATH) && existing.start_with?(readme_marker)
      end

      def write_files(files)
        # Narrow accidental-change windows; same-target concurrent writers are unsupported.
        preflight_directories
        preflight_files(files)
        preflight_permissions(files)
        FileUtils.mkdir_p(Configuration::Paths.at(@root, Initializer::LAYOUT.command_directory))
        preflight_directories
        files.each do |path, content|
          preflight_directories
          preflight_files(path => content)
          write_new_file(path, content) unless File.file?(path)
        end
      end

      def write_new_file(path, content)
        Configuration.create_generated_file(root: @root, path:, content:, mode: destination_mode(path))
      end

      def destination_mode(path) = wrapper_path?(path) ? 0o755 : 0o644

      def wrapper_path?(path)
        File.dirname(path) == Configuration::Paths.at(@root, Initializer::LAYOUT.command_directory)
      end
    end
  end
end
