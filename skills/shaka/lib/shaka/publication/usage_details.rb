# frozen_string_literal: true

require 'json'
require_relative '../error'
require_relative '../usage/usage_records'
require_relative 'text'
require_relative 'usage_rows'
require_relative 'usage_pricing'

module Shaka
  # Checks each usage column is the flat, single-line record `shaka usage --format json` prints.
  module UsageColumnCheck
    KEYS = %w[label provider model routed effort credits usd input cached_input output reasoning_output
              cache_writes].freeze

    private

    def columns(value)
      raise Error, 'Publication usage record columns must be a list.' unless value.is_a?(Array)
      raise Error, 'Publication usage record columns must include at least one column.' if value.empty?

      value.map.with_index { |column, index| column_cells(column, index) }
    end

    def column_cells(column, index)
      raise Error, "Publication usage column #{index + 1} must be an object." unless column.is_a?(Hash)

      column_keys(column, index)
      KEYS.to_h { |key| [key, cell(column, key, index)] }
    end

    def column_keys(column, index)
      missing = KEYS - column.keys
      extra = column.keys - KEYS
      return if missing.empty? && extra.empty?

      problem = missing.empty? ? "unknown fields: #{extra.join(', ')}" : "missing fields: #{missing.join(', ')}"
      raise Error, "Publication usage column #{index + 1} has #{problem}."
    end

    def cell(column, key, index)
      value = column[key]
      unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
        raise Error, "Publication usage column #{index + 1} #{key} must be single-line nonempty text."
      end

      text = value.strip
      # These two sequences would close the comment that keeps a record's columns.
      raise Error, "Publication usage column #{index + 1} #{key} must not close a comment." if text.match?(/--!?>/)
      # Kept raw in the hidden record, a tag here would fail the carry shape check and drop the report.
      raise Error, "Publication usage column #{index + 1} #{key} must not contain < or >." if text.match?(/[<>]/)

      text
    end
  end

  # Renders the PR usage table so every host publishes the same rows and alignment.
  class UsageDetails
    include UsageColumnCheck

    SUMMARY = 'Usage and cost'
    REQUIRED = %w[note records].freeze
    OPTIONAL = %w[carried].freeze
    # Each record's columns ride in a comment, so a later publish can put them back in the table.
    HIDDEN = /^<!-- usage-columns (.*) -->$/

    def self.usage_summary?(summary) = summary.to_s.match?(/usage/i)

    def initialize(spec)
      @spec = spec
    end

    def detail
      checked
      fresh = @records.flat_map { |entry| hosted(entry['columns'], entry['identity']) }
      rows = UsageRows.new(fresh + carried_columns, earlier: earlier_reports.any?)
      { 'summary' => [SUMMARY, rows.summary].compact.join(' · '), 'body' => body(rows) }
    end

    private

    def body(rows)
      parts = [rows.table, rows.legend, rows.glossary, UsagePricing.details(pricing_pairs)]
      parts << @note unless @note.empty?
      parts.concat(earlier_reports)
      parts.concat(record_blocks)
      parts.compact.join("\n\n")
    end

    def checked
      raise Error, 'Publication usage must be an object.' unless @spec.is_a?(Hash)

      refuse_keys(@spec.keys - (REQUIRED + OPTIONAL), 'has unknown fields')
      refuse_keys(REQUIRED - @spec.keys, 'is missing fields')
      @note = note(@spec['note'])
      @carried = carried_blocks
      @records = records
    end

    def refuse_keys(keys, problem)
      raise Error, "Publication usage #{problem}: #{keys.join(', ')}." unless keys.empty?
    end

    def note(value)
      raise Error, 'Publication usage note must be text.' unless value.is_a?(String)

      # The same checks as a record's note keep this one from closing the usage disclosure.
      UsagePricing.checked(value).to_s
    end

    # Carry sets this from the published body; a record's columns join the table,
    # and a report from before the table existed stays below it as it was.
    def carried_blocks
      return [] unless @spec.key?('carried')

      value = @spec['carried']
      raise Error, 'Publication usage carried must be text.' unless value.is_a?(String)

      text = PublicationText.checked(value.strip, 'usage carried')
      text.to_enum(:scan, UsageRecords::BLOCK).map { Regexp.last_match[0] }
    end

    def carried_columns
      @carried.flat_map do |block|
        hidden = block[HIDDEN, 1]
        hidden ? hosted(columns(parse_hidden(hidden)), UsageRecords.text_records(block).first) : []
      end
    end

    # Hosts count input differently, so rows only combine reports from one host.
    def hosted(columns, identity)
      unless identity
        raise Error,
              'A carried usage record has an unreadable identity; restore or remove it in the PR body.'
      end

      columns.map { |column| column.merge('host' => identity['host']) }
    end

    def parse_hidden(text)
      JSON.parse(text)
    rescue JSON::ParserError
      raise Error, 'A carried usage record has unreadable columns; restore or remove it in the PR body.'
    end

    def earlier_reports = @carried.grep_v(HIDDEN)

    # One [label, note] pair per shown report, fresh and carried alike.
    def pricing_pairs
      fresh = @records.flat_map { |entry| entry['columns'].map { |column| [column['label'], entry['note']] } }
      carried = @carried.grep(HIDDEN).flat_map do |block|
        note = UsagePricing.from_block(block)
        columns(parse_hidden(block[HIDDEN, 1])).map { |column| [column['label'], note] }
      end
      fresh + carried
    end

    # Every row comes from a record, so a later publish can carry what this one showed.
    def records
      value = @spec['records']
      unless value.is_a?(Array) && !value.empty?
        raise Error, 'Publication usage records must be a list with at least one record.'
      end

      # A record copied twice is one report, as carry treats one identity; counting it twice would
      # double its cost.
      value.map { |fields| record_entry(fields) }.uniq { |entry| entry['identity'] }
    end

    def record_entry(fields)
      raise Error, 'Publication usage record must be an object.' unless fields.is_a?(Hash)

      copied = fields.dup
      nested = copied.delete('columns')
      note = UsagePricing.checked(copied.delete('note'))
      { 'identity' => UsageRecordCarry.identity!(copied), 'columns' => columns(nested), 'note' => note }
    end

    # Carried record blocks stay hidden and unchanged, so the next publish can read them again.
    def record_blocks
      fresh = @records.map do |entry|
        hidden = ["<!-- usage-columns #{JSON.generate(entry['columns'])} -->", UsagePricing.hidden(entry['note'])]
        "#{UsageRecords.begin_mark(entry['identity'])}\n#{hidden.compact.join("\n")}\n#{UsageRecords::END_MARK}"
      end
      @carried.grep(HIDDEN) + fresh
    end
  end
end
