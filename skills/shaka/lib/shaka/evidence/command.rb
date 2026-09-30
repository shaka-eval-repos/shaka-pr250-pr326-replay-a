# frozen_string_literal: true

require 'json'
require 'open3'
require_relative '../error'
require_relative '../local_review/path_guard'
require_relative 'candidate_tree'
require_relative 'inputs'
require_relative 'options'
require_relative 'result'
require_relative 'verification'

module Shaka
  module Evidence
    # Executes, binds, and verifies check results without a separate ledger.
    class Command
      include Options

      NAMES = %w[setup test validate validate_local trigger_hosted_ci].freeze
      Execution = Data.define(:process, :before_tree, :after_tree, :after_settings, :after_kind)

      def self.run(arguments)
        new(arguments).run
      rescue KeyError => e
        warn "shaka: Missing --#{e.key}"
        1
      rescue Error, OptionParser::ParseError, JSON::ParserError, SystemCallError => e
        warn "shaka: #{e.message}"
        1
      end

      def initialize(arguments)
        @arguments = arguments.dup
        @options = {}
      end

      def run
        @original_path = ENV.fetch('PATH', nil)
        action = action!
        flags = parser(action)
        flags.parse!(@arguments)
        return 0.tap { puts flags } if @options[:help]

        result = send({ 'run' => :run_fixed, 'bind' => :bind_result, 'verify' => :verify_results }.fetch(action))
        puts JSON.pretty_generate(result)
        %w[completed bound ready].include?(result.fetch('status')) ? 0 : 1
      ensure
        ENV['PATH'] = @original_path
      end

      private

      def action!
        action = @arguments.shift
        return action if %w[run bind verify].include?(action)

        raise OptionParser::InvalidArgument, 'Usage: shaka evidence (run|bind|verify) [options]'
      end

      def common
        root = File.realpath(@options.fetch(:root))
        ENV['PATH'] = LocalReviewPathGuard.safe_path(ENV.fetch('PATH', ''), candidate_root: root, drop_candidate: true)
        ref = @options.fetch(:ref)
        repository = @options.fetch(:repository)
        raise Error, '--ref must be a full commit SHA' unless ref.match?(Result::SHA)

        [root, ref, repository]
      rescue KeyError => e
        raise Error, "Missing --#{e.key}"
      end

      def run_fixed = execute_run(prepare_run)

      def prepare_run
        root, ref, repository = common
        name = @options[:command] || raise(Error, 'Missing --command')
        raise Error, "Unknown fixed command #{name}" unless NAMES.include?(name)

        task_overrides = { 'command' => name, 'arguments' => @arguments }
        config, settings, kind = Inputs.capture(root:, ref:, repository:, task_overrides:)
        { root:, ref:, repository:, name:, task_overrides:, settings:, kind:, path: config.command(name) }
      end

      def execute_run(context)
        root = context.fetch(:root)
        before_tree = CandidateTree.capture(root:)
        output, error, process = Open3.capture3({ 'PATH' => @original_path }, File.join(root, context.fetch(:path)),
                                                *@arguments, chdir: root)
        $stderr.write(output, error)
        after_tree = CandidateTree.capture(root:)
        _config, after_settings, after_kind = Inputs.capture(root:, ref: context.fetch(:ref),
                                                             repository: context.fetch(:repository),
                                                             task_overrides: context.fetch(:task_overrides))
        run_result(context, Execution.new(process:, before_tree:, after_tree:, after_settings:, after_kind:))
      end

      def run_result(context, execution)
        changed = inputs_changed?(context, execution)
        { 'kind' => 'validation', 'command' => context.fetch(:name),
          'status' => execution.process.success? && !changed ? 'completed' : 'not_completed',
          'exit_code' => execution.process.exitstatus, 'tested_tree' => execution.before_tree,
          'settings' => context.fetch(:settings), 'inputs_changed' => changed,
          'tree_after' => execution.after_tree, 'settings_after' => execution.after_settings,
          'repository' => context.fetch(:repository), 'source_ref' => context.fetch(:ref),
          'source_kind' => context.fetch(:kind), 'task_overrides' => context.fetch(:task_overrides) }
      end

      def inputs_changed?(context, execution)
        execution.before_tree != execution.after_tree || context.fetch(:settings) != execution.after_settings ||
          context.fetch(:kind) != execution.after_kind
      end

      def bind_result
        root, ref, repository = common
        raise Error, 'bind accepts no command arguments' unless @arguments.empty?

        path = Result.local_file!(root, @options.fetch(:result))
        original = JSON.parse(File.read(path, encoding: 'UTF-8'))
        Result.bind(original, root:, head: @options.fetch(:head), ref:, repository:)
      end

      def verify_results
        root, ref, repository = common
        raise Error, 'verify accepts no command arguments' unless @arguments.empty?

        Verification.new(root:, ref:, repository:, head: @options.fetch(:head), paths: @options).run
      end
    end
  end
end
