# frozen_string_literal: true

require 'digest'
require 'open3'
require_relative '../../error'
require_relative '../../trusted_path_resolver'
require_relative 'canonical'

module Shaka
  module Configuration
    # Reads configured prompt bytes from the same commit used by review/opening commands.
    class FingerprintTrustedPrompts
      def initialize(root:, ref:)
        @root = root
        @ref = ref
        @resolver = TrustedPathResolver.new(root:, sha: ref)
      end

      def hashes(paths)
        paths.uniq.sort.to_h { |path| [path, FingerprintCanonical.digest('file', identity(path))] }
      end

      private

      def identity(path)
        resolved, entry = @resolver.resolve(path)
        raise Error, "Trusted prompt #{path} is not a file at #{@ref}" unless entry && entry.last == 'blob'

        mode = entry.first.to_i(8) & 0o777
        result = { 'type' => 'regular', 'resolved_path' => resolved, 'mode' => mode,
                   'bytes_sha256' => Digest::SHA256.hexdigest(git('show', "#{@ref}:#{resolved}")) }
        link = @resolver.entry(path)
        return result unless link == TrustedPathResolver::SYMLINK

        result.merge('type' => 'symlink', 'target' => symlink_target(path))
      end

      def symlink_target(path)
        target = git('show', "#{@ref}:#{path}").dup.force_encoding(Encoding::UTF_8)
        raise Error, "Trusted prompt symlink #{path} is not UTF-8" unless target.valid_encoding?

        target
      end

      def git(*)
        out, err, status = Open3.capture3('git', '-C', @root, *, binmode: true)
        raise Error, "Cannot read trusted prompt: #{err.strip}" unless status.success?

        out
      end
    end
  end
end
