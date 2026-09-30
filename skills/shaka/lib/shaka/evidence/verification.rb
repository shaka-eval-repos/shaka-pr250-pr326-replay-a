# frozen_string_literal: true

require 'json'
require_relative 'inputs'
require_relative 'result'

module Shaka
  module Evidence
    # Checks supplied results at the proposed head; absence is explicit, never inferred.
    class Verification
      def initialize(root:, ref:, repository:, head:, paths:)
        @root = root
        @ref = ref
        @repository = repository
        @head = head
        @paths = paths
      end

      def run
        config, = Inputs.capture(root: @root, ref: @ref, repository: @repository)
        @accepted = config.commands.key?('validate_local') ? %w[validate_local validate] : ['validate']
        checks = %w[validation review].to_h { |kind| [kind, entries(kind)] }
        missing = checks.select { |_kind, values| values.empty? }.keys
        ready = missing.empty? && checks.values.flatten.all? { |entry| entry['status'] == 'bound' }
        { 'status' => ready ? 'ready' : 'not_ready', 'head' => @head,
          'missing' => missing, 'checks' => checks }
      end

      private

      def entries(kind)
        Array(@paths[kind.to_sym]).map { |path| check(path, kind) }
      end

      def check(path, kind)
        return { 'status' => 'missing', 'path' => path, 'reasons' => ['result file missing'] } unless File.file?(path)

        original = JSON.parse(File.read(Result.local_file!(@root, path), encoding: 'UTF-8'))
        binding = Result.bind(original, root: @root, head: @head, ref: @ref, repository: @repository)
        check_kind(kind, original, binding)
      end

      def check_kind(kind, original, binding)
        binding['reasons'] << "expected #{kind} result" unless original['kind'] == kind
        if kind == 'validation'
          binding['reasons'] << 'expected repository validation command' unless @accepted.include?(original['command'])
          binding['reasons'] << 'repository validation used command arguments' unless
            original.dig('task_overrides', 'arguments') == []
        end
        binding['status'] = 'superseded' unless binding['reasons'].empty?
        binding
      end
    end
  end
end
