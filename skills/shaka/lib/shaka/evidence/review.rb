# frozen_string_literal: true

require 'open3'
require_relative '../workflow_version'
require_relative '../local_review/path_guard'
require_relative 'candidate_tree'
require_relative 'inputs'
require_relative 'result'

module Shaka
  module Evidence
    # Adds content and settings identities to the review runner's result.
    class Review
      def self.start(options, action:)
        return unless options[:settings_ref]

        raise Error, '--repository is required with --settings-ref' unless options[:repository]
        raise Error, '--root is required with --settings-ref' unless options[:root]

        ref = reviewed_ref(options, action)
        root = safe_root(options[:root])
        new(root:, ref:, repository: options[:repository], action:, options:).tap(&:capture_before)
      end

      def self.safe_root(root)
        return unless root

        directory = File.realpath(root)
        ENV['PATH'] =
          LocalReviewPathGuard.safe_path(ENV.fetch('PATH', ''), candidate_root: directory, drop_candidate: true)
        directory
      end

      def self.reviewed_ref(options, action)
        align_refs!(options) if action == 'run'
        options[:settings_ref]
      end

      def self.align_refs!(options)
        return unless options[:settings_ref]
        if options[:criteria_ref] && options[:criteria_ref] != options[:settings_ref]
          raise Error, 'Review criteria and settings refs must match'
        end

        options[:criteria_ref] ||= options[:settings_ref]
      end

      def initialize(root:, ref:, repository:, action:, options:)
        @root = File.realpath(root)
        @ref = ref
        @repository = repository
        @action = action
        @task_overrides = { 'reviewer' => options[:reviewer]&.downcase,
                            'model' => options[:model], 'effort' => options[:effort] }.compact
      end

      def capture_before
        @candidate_before = CandidateTree.capture(root: @root)
        @dirty_before = dirty?
        _config, @settings_before, @source_kind = Inputs.capture(root: @root, ref: @ref,
                                                                 repository: @repository,
                                                                 task_overrides: @task_overrides)
      end

      def finish(result)
        candidate_after = CandidateTree.capture(root: @root)
        _config, settings_after, source_kind_after = Inputs.capture(root: @root, ref: @ref,
                                                                    repository: @repository,
                                                                    task_overrides: @task_overrides)
        head = result['head']
        commit_tree = Result.commit_tree(@root, head) if head&.match?(Result::SHA)
        changed = candidate_after != @candidate_before || settings_after != @settings_before ||
                  source_kind_after != @source_kind
        result.merge(result_fields(candidate_after, settings_after, commit_tree, changed))
      end

      private

      def result_fields(candidate_after, settings_after, commit_tree, changed)
        { 'kind' => 'review', 'tested_tree' => commit_tree, 'settings' => @settings_before,
          'candidate_tree_before' => @candidate_before, 'candidate_tree_after' => candidate_after,
          'settings_after' => settings_after, 'inputs_changed' => changed,
          'review_provisional' => @dirty_before || @candidate_before != commit_tree,
          'repository' => @repository, 'source_ref' => @ref, 'source_kind' => @source_kind,
          'task_overrides' => @task_overrides,
          'settings_basis' => @action == 'run' ? 'observed_during_review' : 'observed_at_review_check' }
      end

      def dirty?
        output, error, status = Open3.capture3(WorkflowVersion::GIT_ENVIRONMENT, 'git', '-C', @root,
                                               'status', '--porcelain', '-z')
        raise Error, "Cannot inspect review checkout: #{error.strip}" unless status.success?

        !output.empty?
      end
    end
  end
end
