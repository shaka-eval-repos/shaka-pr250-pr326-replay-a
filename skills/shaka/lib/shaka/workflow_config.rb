# frozen_string_literal: true

require 'yaml'
require_relative 'error'
require_relative 'repository_config/duplicate_keys'

module Shaka
  # Loads the packaged, declarative delivery workflow.
  class WorkflowConfig
    PATH = File.expand_path('../../config/workflow.yml', __dir__)
    PHASE_IDS = %w[intake plan implement verify explain review finish].freeze
    ROOT_KEYS = %w[version title purpose phases always code_quality].freeze
    PHASE_KEYS = %w[id title body done_when].freeze

    def self.load(source: nil)
      new(source: source || File.read(PATH, encoding: 'UTF-8')).load
    end

    def initialize(source:)
      @source = source
    end

    def load
      RepositoryConfig::DuplicateKeys.check(@source, filename: 'workflow.yml')
      data = YAML.safe_load(@source, permitted_classes: [], permitted_symbols: [], aliases: false)
      validate(data)
      data
    rescue Psych::Exception => e
      raise Error, "Invalid workflow.yml: #{e.message}"
    end

    private

    def validate(data)
      mapping!(data, 'workflow')
      exact_keys!(data, ROOT_KEYS, 'workflow')
      raise Error, 'workflow version must be 1' unless data['version'] == 1

      %w[title purpose always code_quality].each { |key| text!(data[key], key) }
      phases!(data['phases'])
    end

    def phases!(phases)
      raise Error, 'phases must be a list' unless phases.is_a?(Array)

      phases.each do |phase|
        mapping!(phase, 'phase')
        exact_keys!(phase, PHASE_KEYS, 'phase')
        PHASE_KEYS.each { |key| text!(phase[key], "phases.#{phase['id'] || '?'}.#{key}") }
      end
      ids = phases.map { |phase| phase['id'] }
      return if ids == PHASE_IDS

      raise Error, "workflow phases must be ordered: #{PHASE_IDS.join(', ')}"
    end

    def mapping!(value, label)
      valid = value.is_a?(Hash) && value.keys.all?(String)
      raise Error, "#{label} must be a mapping with string keys" unless valid
    end

    def exact_keys!(mapping, expected, label)
      unknown = mapping.keys - expected
      missing = expected - mapping.keys
      raise Error, "unknown #{label} key: #{unknown.first}" unless unknown.empty?
      raise Error, "missing #{label} key: #{missing.first}" unless missing.empty?
    end

    def text!(value, label)
      raise Error, "#{label} must be non-empty text" unless value.is_a?(String) && !value.strip.empty?
    end
  end
end
