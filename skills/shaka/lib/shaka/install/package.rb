# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'package_verification'

module Shaka
  module Install
    # Copies selected skills into a managed directory; see install/README.md.
    class Package
      include PackageVerification

      METADATA = '.shaka-install.json'
      ALLOWED = %w[shaka rct mct-claude rct-claude].freeze
      ID_PATTERN = /\A[A-Za-z0-9._+-]+-[0-9a-f]{64}-[0-9a-f]{64}\z/

      def self.identity_for(version, source)
        "#{version}-#{source.fetch('content_sha256')}-#{Digest::SHA256.hexdigest(JSON.generate(source))}"
      end

      def self.valid_skills?(names)
        names.is_a?(Array) && names.include?('shaka') && names.uniq == names && (names - ALLOWED).empty?
      end

      def initialize(root, source, names, tree)
        @root = root
        @source = source
        @names = names
        @tree = tree
      end

      def prepare(source_root)
        ensure_managed_root
        hash = @tree.hash(source_root, normalized: true)
        identity = @source.identity(hash)
        version = @source.version
        id = identity_for(version, identity)
        target = File.join(@root, id)
        return reuse(target, source_root, hash, identity, version) if File.exist?(target) || File.symlink?(target)

        stage(source_root, target, identity, version)
      end

      def existing(id)
        verify_managed_root
        raise ArgumentError, 'Invalid package identity' unless id.match?(ID_PATTERN)

        path = File.join(@root, id)
        metadata = verified_metadata(path)
        raise ArgumentError, 'Rollback flags must match the package skills' unless metadata.fetch('skills') == @names

        path
      end

      def verify(path)
        verified_metadata(path)
        path
      end

      private

      def reuse(target, source_root, hash, identity, version)
        verify(target)
        verify_source(source_root, hash, identity, version)
        target
      end

      def verify_source(source_root, hash, identity, version)
        current_hash = @tree.hash(source_root, normalized: true)
        raise ArgumentError, 'Source changed during installation' unless current_hash == hash
        raise ArgumentError, 'Source identity changed during installation' unless @source.identity(hash) == identity
        raise ArgumentError, 'Source version changed during installation' unless @source.version == version
      end

      def identity_for(version, source)
        self.class.identity_for(version, source)
      end

      def stage(source_root, target, identity, version)
        staging = Dir.mktmpdir('.staging-', @root)
        begin
          build(staging, source_root, target, identity, version)
        ensure
          FileUtils.chmod_R(0o700, staging) if File.directory?(staging)
          FileUtils.rm_rf(staging)
        end
        target
      end

      def build(staging, source_root, target, identity, version)
        hash = identity.fetch('content_sha256')
        @tree.copy(source_root, staging)
        raise ArgumentError, 'Source changed during installation' unless @tree.hash(staging) == hash

        verify_source(source_root, hash, identity, version)

        write_metadata(staging, target, identity, version)
        @tree.reject_checkout_references(staging, source_root)
        publish(staging, target)
      end

      def write_metadata(staging, target, identity, version)
        metadata = { 'schema_version' => 1, 'package_id' => File.basename(target),
                     'version' => version, 'skills' => @names, 'source' => identity }
        File.write(File.join(staging, METADATA), "#{JSON.pretty_generate(metadata)}\n")
        File.chmod(0o644, File.join(staging, METADATA))
      end

      def publish(staging, target)
        File.chmod(0o755, staging)
        File.rename(staging, target)
      rescue Errno::EEXIST, Errno::ENOTEMPTY
        verify(target)
      end

      def validate_metadata(path, metadata)
        raise ArgumentError, 'Managed package metadata must be an object' unless metadata.is_a?(Hash)

        names = metadata.fetch('skills')
        raise ArgumentError, 'Managed package skills are invalid' unless self.class.valid_skills?(names)

        source = metadata.fetch('source')
        raise ArgumentError, 'Managed package source must be an object' unless source.is_a?(Hash)

        validate_identity(path, metadata, source)
        return if @tree.hash(path, names) == source.fetch('content_sha256')

        raise ArgumentError, 'Managed package content differs'
      end

      def validate_identity(path, metadata, source)
        expected = identity_for(metadata.fetch('version'), source)
        return if metadata['package_id'] == expected && File.basename(path) == expected

        raise ArgumentError, 'Managed package identity differs'
      end
    end
  end
end
