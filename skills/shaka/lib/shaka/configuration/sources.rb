# frozen_string_literal: true

require 'open3'
require 'yaml'
require_relative '../repository_config'
require_relative '../review_prompt'
require_relative '../trusted_path_resolver'
require_relative 'layout'

module Shaka
  module Configuration
    # Source selection and immutable Git-tree reads for repository configuration.
    module Sources
      def default_ref(root:)
        refs = %w[origin/HEAD origin/main origin/master]
        refs.find { |ref| commit_exists?(root:, ref:) } ||
          raise(Error, 'Cannot resolve origin/HEAD or origin/main as a trusted commit')
      end

      def resolve_commit(root:, ref:, label:)
        sha, error, status = Open3.capture3('git', '-C', root, 'rev-parse', '--verify', '--end-of-options',
                                            "#{ref}^{commit}")
        raise Error, "Invalid #{label} #{ref}: #{error.strip}" unless status.success?

        sha.strip
      end

      def commit_exists?(root:, ref:)
        _sha, _error, status = Open3.capture3('git', '-C', root, 'rev-parse', '--verify', '--end-of-options',
                                              "#{ref}^{commit}")
        status.success?
      end

      def read_at_commit(root:, sha:, path: Paths::CONTRACT, display_ref: sha)
        source, error, status = Open3.capture3('git', '-C', root, 'show', "#{sha}:#{path}")
        raise Error, "Cannot read #{path} at #{display_ref}: #{error.strip}" unless status.success?

        source
      end

      def contract_at_commit?(root:, ref:, git:)
        sha, error, status = git.call('-C', root, 'rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}")
        raise Error, "Invalid trusted ref #{ref}: #{error.strip}" unless status.success?

        !Layout.commit(root:, sha: sha.strip, allow_missing: true, git:).nil?
      end

      def entry_at_commit?(sha:, path:, root:)
        _out, status = Open3.capture2e('git', '-C', root, 'cat-file', '-e', "#{sha}:#{path}")
        status.success?
      end

      # Migration reads predecessor shape without applying the current schema.
      def predecessor(root:, sha:, ref: sha)
        source = read_at_commit(root:, sha:, display_ref: ref)
        RepositoryConfig::DuplicateKeys.check(source, filename: Paths::CONTRACT)
        [source, YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)]
      rescue Psych::Exception => e
        raise Error, "Invalid #{Paths::CONTRACT}: #{e.message}"
      end

      # Review instructions intentionally tolerate unrelated, incomplete seam fields.
      def review_at_commit(root:, ref:, git:, capture:, probe:)
        sha = capture.call(git, '-C', root, 'rev-parse', '--verify', '--end-of-options', "#{ref}^{commit}").strip
        layout = Layout.commit(root:, sha:, allow_missing: true, git: probe) || Layout::LEGACY
        source = capture.call(git, '-C', root, 'show', "#{sha}:#{layout.contract}")
        data = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
        review = data.is_a?(Hash) ? data['review'] : nil
        review.is_a?(Hash) ? review : {}
      rescue Psych::Exception => e
        raise Error, "Invalid #{layout.contract} at #{sha}: #{e.message}"
      end

      def prompt_at_commit(root:, ref:, path:, git_access:)
        resolved = resolved_prompt_path(root:, ref:, path:, git_access:)
        prompt_source(root:, ref:, path:, resolved:, git_access:)
      end

      def resolved_prompt_path(root:, ref:, path:, git_access:)
        resolved, entry = TrustedPathResolver.new(root:, sha: ref, git: git_access.fetch(:resolver)).resolve(path)
        return resolved if entry && entry.last == 'blob' && entry.first != TrustedPathResolver::SYMLINK.first

        raise Error, "Review prompt file #{path} is not a file at #{ref}"
      end

      def prompt_source(root:, ref:, path:, resolved:, git_access:)
        blob = lambda do |option|
          git_access.fetch(:capture).call(git_access.fetch(:executable), '-C', root, 'cat-file', option,
                                          "#{ref}:#{resolved}")
        end
        text = nil
        error = ReviewPrompt.file_error(blob.call('-s').to_i) { text = blob.call('-p') }
        raise Error, "Review prompt file #{path} at #{ref} #{error}" if error

        text
      end

      private :commit_exists?, :resolved_prompt_path, :prompt_source
    end
  end
end
