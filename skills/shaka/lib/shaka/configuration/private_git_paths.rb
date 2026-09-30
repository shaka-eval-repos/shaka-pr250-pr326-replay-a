# frozen_string_literal: true

require 'open3'
require_relative 'paths'
require_relative '../error'

module Shaka
  module Configuration
    # Keep invalid Git path bytes intact while matching valid paths to filesystem strings.
    module PrivateGitPaths
      module_function

      # Git's repository-local variables override -C, including its index and object store.
      GIT_ENVIRONMENT = %w[GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
                           GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE
                           GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX
                           GIT_SHALLOW_FILE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES]
                        .to_h { |name| [name, nil] }.freeze

      def command(*) = Open3.capture3(GIT_ENVIRONMENT, 'git', *)
      def capture(root, *) = command('-C', root, *)

      def parse(output)
        output.b.split("\0".b).map do |path|
          native = path.dup.force_encoding(Encoding::UTF_8)
          native.valid_encoding? ? native : path
        end
      end

      def committed(root:, git:)
        _, _, status = capture(root, 'rev-parse', '--verify', '--quiet', 'HEAD^{commit}')
        return parse(git.call('ls-tree', '-r', '-z', '--name-only', 'HEAD')).to_set if status.success?

        branch, _, symbolic = capture(root, 'symbolic-ref', '--quiet', 'HEAD')
        raise Error, 'Cannot inspect candidate HEAD' unless symbolic.success?

        _, _, existing = capture(root, 'show-ref', '--verify', '--quiet', branch.strip)
        raise Error, 'Cannot inspect candidate HEAD' unless existing.exitstatus == 1

        Set.new
      end

      def verify_trusted_tree!(sha:, git:)
        paths = parse(git.call('ls-tree', '-r', '-z', '--name-only', sha, Paths::DIRECTORY))
        [Paths::CONTRACT, Paths::NEW_CONTRACT].each do |path|
          git.call('cat-file', '-e', "#{sha}:#{path}") if paths.include?(path)
        end
      end
    end
  end
end
