# frozen_string_literal: true

require 'open3'
require_relative 'error'
require_relative 'version'
require_relative 'doctor/installation_identity'

module Shaka
  # Names the workflow code that is running. Every commit between releases shares one
  # VERSION, so the commit identifies the code: the revision the managed installer recorded,
  # or the HEAD of the checkout the helper runs from directly. `modified` marks a copy whose
  # skill files differ from that commit. Reading a checkout needs `git`, a Git executable
  # the caller has vetted against the candidate checkout; without one the commit is unknown.
  module WorkflowVersion
    ROOT = File.expand_path('../../../..', __dir__)
    SKILL = 'skills/shaka'
    # `git rev-parse --local-env-vars`: inherited from a Git hook or wrapper, these would
    # point Git at another repository's files, objects, or configuration.
    GIT_ENVIRONMENT = %w[GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
                         GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE
                         GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX
                         GIT_SHALLOW_FILE GIT_COMMON_DIR].to_h { |name| [name, nil] }.freeze

    REPOSITORY = 'https://github.com/shakacode/shaka'
    # Remote spellings of REPOSITORY; a commit from any other source may exist only in a fork.
    UPSTREAM = %r{\A(?:https://github\.com/|git@github\.com:|ssh://(?:git@)?github\.com/)shakacode/shaka(?:\.git)?/?\z}i
    COMMIT = /\A(?:\h{40}|\h{64})\z/
    # The installer's version grammar (Install::Version), so any installed package can fall back.
    RELEASE = /\A[A-Za-z0-9][A-Za-z0-9._+-]*\z/

    # Renders the commit, linked when it came from REPOSITORY, or the release version when no
    # commit is known. Installation metadata is only type-checked, so each part is checked
    # before it reaches the table.
    Result = Data.define(:version, :commit, :modified, :upstream) do
      def markdown
        return "#{link}#{' (modified)' if modified}" if commit

        raise Error, 'Workflow version is invalid.' unless version.is_a?(String) && version.match?(RELEASE)

        "`#{version}` (commit unknown#{', modified' if modified})"
      end

      private

      def link
        raise Error, 'Workflow commit is invalid.' unless commit.is_a?(String) && commit.match?(COMMIT)

        upstream ? "[`#{commit[0, 7]}`](#{REPOSITORY}/commit/#{commit})" : "`#{commit}`"
      end
    end

    module_function

    def current(identity: read_identity, root: ROOT, git: nil)
      identity ||= {}
      source = identity['source'] || {}
      commit, modified, repository = commit(source, root, git)
      Result.new(version: identity['version'] || VERSION, commit: matching(commit, COMMIT),
                 modified: modified || false, upstream: !matching(repository, UPSTREAM).nil?)
    end

    # Installation metadata is only type-checked, so a malformed value counts as unknown.
    def matching(value, pattern) = (value if value.is_a?(String) && value.match?(pattern))

    def commit(source, root, git)
      case source['kind']
      when 'revision' then [source['revision'], false, source['repository']]
      when 'development' then [source['base_revision'], true, source['repository']]
      when 'uninstalled' then git ? checkout_commit(root, git) : [nil, false]
      else [nil, false]
      end
    end

    def read_identity
      Doctor::InstallationIdentity.read
    rescue Error, KeyError, TypeError, SystemCallError
      nil
    end

    def checkout_commit(root, git)
      return [nil, false] unless run(git, root, 'rev-parse', '--show-toplevel') == File.realpath(root)

      head = run(git, root, 'rev-parse', '--verify', 'HEAD')
      status = run(git, root, 'status', '--porcelain', '--untracked-files=all', '--', SKILL)
      entries = run(git, root, 'ls-files', '-v', '--', SKILL)
      return [nil, false] unless head && status && entries

      [head, !status.empty? || index_flags?(entries), published_origin(git, root, head)]
    end

    # The origin URL, only when an origin branch already contains the commit: matching the URL
    # alone would link a local, unpushed commit. Remote-tracking refs need no network call.
    def published_origin(git, root, head)
      held = run(git, root, 'for-each-ref', '--count=1', '--contains', head, 'refs/remotes/origin')
      run(git, root, 'config', '--get', 'remote.origin.url') unless held.to_s.empty?
    end

    # `git status` hides edits to assume-unchanged (lowercase tag) and skip-worktree (`S`)
    # files, so any tag other than a plain cached `H` means status cannot vouch for them.
    def index_flags?(entries) = entries.lines.any? { |line| !line.start_with?('H ') }

    # Runs from the helper's own directory: a `git` wrapper on PATH may load files relative
    # to its working directory, which is often a candidate checkout.
    def run(git, root, *)
      output, status = Open3.capture2(GIT_ENVIRONMENT, git, *, chdir: root, err: File::NULL)
      output.strip if status.success?
    rescue SystemCallError
      nil
    end

    private_class_method :read_identity, :matching, :commit, :checkout_commit, :published_origin, :index_flags?, :run
  end
end
