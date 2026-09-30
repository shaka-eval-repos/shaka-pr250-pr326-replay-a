# frozen_string_literal: true

require 'open3'
require_relative '../error'
require_relative '../configuration/fingerprint/canonical'
require_relative '../workflow_version'
require_relative 'inputs'

module Shaka
  module Evidence
    # Compares a result without rewriting the identity it originally recorded.
    class Result
      SHA = /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/

      def self.bind(result, root:, head:, ref:, repository:)
        new(result, root:, head:, ref:, repository:).bind
      end

      def initialize(result, root:, head:, ref:, repository:)
        @result = result
        @root = root
        @head = head
        @ref = ref
        @repository = repository
      end

      def bind
        raise Error, 'Evidence result must be an object' unless @result.is_a?(Hash)
        raise Error, 'Head must be a full commit SHA' unless @head.to_s.match?(SHA)

        tree = self.class.commit_tree(@root, @head)
        _config, settings, source_kind = Inputs.capture(root: @root, ref: @ref, repository: @repository,
                                                        task_overrides: @result.fetch('task_overrides', {}))
        changed = self.class.component_changes(@result['settings'], settings)
        reasons = result_reasons(tree) + settings_reasons(source_kind, changed)
        binding_result(tree, changed, reasons)
      end

      def binding_result(tree, changed, reasons)
        { 'status' => reasons.empty? ? 'bound' : 'superseded', 'head' => @head,
          'commit_tree' => tree, 'tested_tree' => @result['tested_tree'],
          'changed_settings_components' => changed, 'reasons' => reasons,
          'rerun' => @result['kind'] || 'affected check', 'original' => @result }
      end

      def result_reasons(tree)
        reasons = completeness_reasons
        reasons << 'inputs changed during check' if @result['inputs_changed']
        reasons << 'review did not inspect committed candidate' if @result['review_provisional']
        reasons << 'review attests another commit' if @result['kind'] == 'review' && @result['head'] != @head
        reasons << 'candidate tree differs from tested tree' if @result['tested_tree'] && @result['tested_tree'] != tree
        reasons
      end

      def completeness_reasons
        reasons = []
        reasons << 'missing tested tree' unless @result['tested_tree'].to_s.match?(SHA)
        reasons << 'missing or invalid settings identity' unless self.class.valid_settings?(@result['settings'])
        reasons << 'check did not complete' unless %w[completed reported].include?(@result['status'])
        if @result['kind'] == 'validation' && @result['command'] != @result.dig('task_overrides', 'command')
          reasons << 'validation command differs from settings command'
        end
        reasons
      end

      def settings_reasons(source_kind, changed)
        reasons = []
        reasons << 'repository differs or is missing' unless @result['repository'] == @repository
        reasons << 'settings source differs or is missing' unless @result['source_kind'] == source_kind
        material = changed - ['source']
        reasons << "settings components differ: #{material.join(', ')}" unless material.empty?
        reasons
      end

      def self.component_changes(original, current)
        return [] unless original.is_a?(Hash) && current.is_a?(Hash)
        return ['version'] unless original['version'] == current['version']

        original_components = original['components'] || {}
        current_components = current['components'] || {}
        (original_components.keys | current_components.keys).sort.reject do |key|
          original_components[key] == current_components[key]
        end
      end

      def self.valid_settings?(settings)
        settings.is_a?(Hash) && settings['version'] == 1 && settings['components'].is_a?(Hash) &&
          settings['digest'] == Configuration::FingerprintCanonical.digest('fingerprint', settings['components'])
      end

      def self.commit_tree(root, head)
        resolved, _error, checked = Open3.capture3(WorkflowVersion::GIT_ENVIRONMENT,
                                                   'git', '-C', root, 'rev-parse', '--verify', '--end-of-options',
                                                   "#{head}^{commit}")
        raise Error, 'Head must identify a commit' unless checked.success? && resolved.strip == head

        output, error, status = Open3.capture3(WorkflowVersion::GIT_ENVIRONMENT,
                                               'git', '-C', root, 'rev-parse', '--verify',
                                               '--end-of-options', "#{head}^{tree}")
        raise Error, "Cannot read commit tree: #{error.strip}" unless status.success?

        output.strip
      end

      def self.local_file!(root, path)
        expanded = File.expand_path(path)
        raise Error, 'Evidence result path is inside candidate checkout' if inside?(root, expanded)

        resolved = File.realpath(expanded)
        raise Error, 'Evidence result resolves inside candidate checkout' if inside?(root, resolved)

        resolved
      end

      def self.inside?(root, path)
        real_root = File.realpath(root)
        path == real_root || path.start_with?("#{real_root}/")
      end

      private :binding_result, :result_reasons, :completeness_reasons, :settings_reasons
    end
  end
end
