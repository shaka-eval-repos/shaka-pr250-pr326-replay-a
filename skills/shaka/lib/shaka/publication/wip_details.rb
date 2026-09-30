# frozen_string_literal: true

require_relative '../error'

module Shaka
  # Renders the WIP Details note as one table, so every host publishes the same fields in the same shape.
  class WipDetails
    SUMMARY = 'WIP Details'
    FIELDS = {
      'owner' => 'Owner',
      'task' => 'Task',
      'thread' => 'Thread',
      'last_observed_activity' => 'Last observed activity',
      'revision' => 'Revision',
      'workspace' => 'Workspace',
      'unfinished_work' => 'Unfinished work',
      'stopped_because' => 'Stopped because',
      'merge_authority' => 'Merge authority',
      'state' => 'State',
      'next_action' => 'Next action'
    }.freeze

    def initialize(spec)
      @spec = spec
    end

    def detail
      { 'summary' => SUMMARY, 'body' => table }
    end

    private

    def table
      rows = validated.map { |key, value| [FIELDS.fetch(key), value] }
      ([%w[Field Value], %w[--- ---]] + rows).map { |row| "| #{row.join(' | ')} |" }.join("\n")
    end

    def validated
      raise Error, 'Publication wip must be an object.' unless @spec.is_a?(Hash)

      refuse_keys(@spec.keys - FIELDS.keys, 'has unknown fields')
      refuse_keys(FIELDS.keys - @spec.keys, 'is missing fields', '; use UNKNOWN')
      FIELDS.keys.to_h { |key| [key, cell(key)] }
    end

    def refuse_keys(keys, problem, advice = '')
      raise Error, "Publication wip #{problem}: #{keys.join(', ')}#{advice}." unless keys.empty?
    end

    # Escaping pipes keeps a value from silently adding a column; escaping backslashes first
    # keeps a value's own backslash from pairing with that escape.
    def cell(key)
      value = @spec[key]
      unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
        raise Error, "Publication wip #{key} must be single-line nonempty text."
      end

      value.strip.gsub(/[\\|]/) { |character| "\\#{character}" }
    end
  end
end
