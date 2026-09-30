# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative '../error'
require_relative '../workflow_version'

module Shaka
  module Evidence
    # Stages the complete nonignored worktree in a disposable Git index and object store.
    # No candidate blob or index update reaches the user's clone.
    class CandidateTree
      def self.capture(root:)
        new(root).capture
      end

      def initialize(root)
        @root = File.realpath(root)
      end

      def capture
        objects = File.realpath(File.expand_path(git('rev-parse', '--git-path', 'objects').strip, @root))
        Dir.mktmpdir('shaka-candidate-tree-') do |directory|
          prepare(directory, objects)
          git('read-tree', 'HEAD')
          git('add', '-A', '--', '.')
          git('write-tree').strip
        ensure
          @environment = nil
        end
      end

      private

      def prepare(directory, objects)
        if directory == @root || directory.start_with?("#{@root}/")
          raise Error, 'Temporary Git directory is inside the candidate checkout'
        end

        isolated = File.join(directory, 'objects')
        FileUtils.mkdir_p(isolated)
        @environment = WorkflowVersion::GIT_ENVIRONMENT.merge(
          'GIT_INDEX_FILE' => File.join(directory, 'index'),
          'GIT_OBJECT_DIRECTORY' => isolated,
          'GIT_ALTERNATE_OBJECT_DIRECTORIES' => objects
        )
      end

      def git(*arguments)
        output, error, status = Open3.capture3(@environment || WorkflowVersion::GIT_ENVIRONMENT,
                                               'git', '-C', @root, *arguments)
        unless status.success?
          raise Error,
                "Cannot capture candidate tree: git #{arguments.first} failed: #{error.strip}"
        end

        output
      end
    end
  end
end
