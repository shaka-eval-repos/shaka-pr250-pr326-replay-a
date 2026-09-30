# frozen_string_literal: true

require 'open3'
require 'uri'
require_relative 'version'

module Shaka
  module Install
    # Records where copied skills came from; see install/README.md.
    class Source
      def initialize(root, names, tree)
        @root = root
        @names = names
        @tree = tree
      end

      def version
        path = File.join(@root, 'skills/shaka/lib/shaka/version.rb')
        Version.read(path)
      end

      def identity(hash)
        revision = git('rev-parse', '--verify', 'HEAD') if git('rev-parse', '--show-toplevel') == @root
        exact = exact_revision?(revision)
        { 'kind' => exact ? 'revision' : 'development', 'repository' => remote,
          'revision' => exact ? revision : nil, 'base_revision' => exact ? nil : revision,
          'content_sha256' => hash }
      end

      private

      def exact_revision?(revision)
        return false unless revision

        tracked = revision_files
        tracked && tracked.keys.sort == selected_files.sort && tracked_directories?(tracked) &&
          clean? && matching_blobs?(tracked)
      end

      def git(*)
        git_raw(*)&.strip
      end

      def git_raw(*)
        output, status = Open3.capture2('git', '-C', @root, *, err: File::NULL)
        output if status.success?
      rescue Errno::ENOENT
        nil
      end

      def revision_files
        listed = git_raw('ls-tree', '-r', '-z', 'HEAD', '--', *@names.map { |name| "skills/#{name}" })
        return unless listed

        listed.split("\0").to_h do |entry|
          header, path = entry.split("\t", 2)
          mode, _type, object = header.split
          [path, [mode, object]]
        end
      end

      def selected_files
        paths = @names.flat_map do |name|
          @tree.entries(@root, name).select { |path| File.file?(path) }
        end
        paths.map { |path| path.delete_prefix("#{@root}/") }
      end

      def tracked_directories?(tracked)
        return false unless @names.all? { |name| tracked.keys.any? { |path| path.start_with?("skills/#{name}/") } }

        selected_directories.all? do |directory|
          relative = directory.delete_prefix("#{@root}/")
          tracked.keys.any? { |path| path.start_with?("#{relative}/") }
        end
      end

      def selected_directories
        @names.flat_map { |name| @tree.entries(@root, name).select { |path| File.directory?(path) } }
      end

      def matching_blobs?(tracked)
        return false unless matching_modes?(tracked)

        tracked.each_slice(100).all? { |batch| matching_blob_batch?(batch) }
      end

      def matching_modes?(tracked)
        tracked.all? do |path, (mode, _object)|
          actual = File.join(@root, path)
          file_mode = File.stat(actual).mode
          expected_mode = file_mode.anybits?(0o100) ? '100755' : '100644'
          file_mode.nobits?(0o002) && mode == expected_mode
        end
      end

      def matching_blob_batch?(batch)
        paths = batch.map { |path,| File.join(@root, path) }
        hashes = git_raw('hash-object', '--no-filters', '--', *paths)&.lines&.map(&:strip)
        hashes == batch.map { |_path, (_mode, object)| object }
      end

      def clean?
        git('status', '--porcelain', '--untracked-files=all', '--',
            *@names.map { |name| "skills/#{name}" }) == ''
      end

      def remote
        return unless git('rev-parse', '--show-toplevel') == @root

        value = git('config', '--get', 'remote.origin.url')
        return value if value&.match?(/\Agit@[^:]+:.+/)

        url_remote(value)
      end

      def url_remote(value)
        return unless value

        address = URI.parse(value)
        ssh = address.scheme&.casecmp?('ssh')
        without_secrets(address, ssh) if (address.is_a?(URI::HTTP) || ssh) && address.host
      rescue URI::InvalidURIError
        nil
      end

      # An HTTP user may be a token and an SSH user may name a person, so only the shared
      # `git` account stays. The default SSH port is dropped so the URL matches the usual spelling.
      def without_secrets(address, ssh)
        address.user = nil unless ssh && address.user == 'git'
        address.password = nil
        address.port = nil if ssh && address.port == 22
        address.query = nil
        address.fragment = nil
        address.to_s
      end
    end
  end
end
