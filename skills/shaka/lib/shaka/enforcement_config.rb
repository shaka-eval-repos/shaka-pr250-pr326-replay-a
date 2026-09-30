# frozen_string_literal: true

require 'yaml'
require_relative 'enforcement_coverage'
require_relative 'error'
require_relative 'repository_config/duplicate_keys'
require_relative 'repository_config/validation'
require_relative 'workflow_config'

module Shaka
  # Loads the audit that records what enforces each rule workflow.yml states with never,
  # must, do not, or only when.
  class EnforcementConfig
    include RepositoryConfig::Validation

    PATH = File.expand_path('../../config/enforcement.yml', __dir__)
    ROOT_KEYS = %w[version rules].freeze
    RULE_KEYS = %w[id phase quote enforced_by].freeze
    BACKED = %w[code reported github].freeze
    ENFORCERS = [*BACKED, 'agent'].freeze

    def self.load(source: nil, workflow: nil)
      source ||= File.read(PATH, encoding: 'UTF-8')
      new(source:, workflow: workflow || WorkflowConfig.load).load
    end

    def initialize(source:, workflow:)
      @source = source
      @workflow = workflow
    end

    def load
      RepositoryConfig::DuplicateKeys.check(@source, filename: 'enforcement.yml')
      data = YAML.safe_load(@source, permitted_classes: [], permitted_symbols: [], aliases: false)
      validate(data)
      data
    rescue Psych::Exception => e
      raise Error, "Invalid enforcement.yml: #{e.message}"
    end

    private

    def validate(data)
      mapping!(data, 'enforcement')
      keys!(data, ROOT_KEYS, [], 'enforcement')
      enum!(data['version'], [1], 'enforcement version must be 1')

      rules = data['rules']
      raise Error, 'enforcement rules must be a non-empty list' unless rules.is_a?(Array) && !rules.empty?

      rules.each { |rule| rule!(rule) }
      unique_ids!(rules)
      EnforcementCoverage.new(@workflow).check(rules)
    end

    def rule!(rule)
      mapping!(rule, 'rule')
      string!(rule['id'], 'rule id')
      label = "rule #{rule['id']}"
      keys!(rule, RULE_KEYS, %w[rule detector note], label)
      string!(rule['rule'], "#{label} rule") if rule.key?('rule')
      RULE_KEYS.each { |key| string!(rule[key], "#{label} #{key}") }
      enforcement!(rule, label)
    end

    # A rule something other than the agent touches names that mechanism; an agent-enforced
    # rule instead says so in as many words, the outcome this audit exists to make visible.
    def enforcement!(rule, label)
      by = rule['enforced_by']
      enum!(by, ENFORCERS, "#{label} enforced_by must be #{ENFORCERS.join(', ')}")

      expected, unexpected = BACKED.include?(by) ? %w[detector note] : %w[note detector]
      string!(rule[expected], "#{label} #{expected}")
      raise Error, "#{label} is #{by}-enforced, so it takes no #{unexpected}" if rule.key?(unexpected)
    end

    def unique_ids!(rules)
      repeated = rules.map { |rule| rule['id'] }.tally.find { |_, count| count > 1 }
      raise Error, "duplicate rule id: #{repeated.first}" if repeated
    end
  end
end
