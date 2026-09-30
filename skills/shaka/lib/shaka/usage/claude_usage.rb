# frozen_string_literal: true

require 'json'
require_relative 'response_count'

module Shaka
  # Claude CLI `-p --output-format json` writes one result object instead of JSONL.
  module ClaudePrintResult
    private

    def print_object(record)
      return unless record.is_a?(Hash) && record['type'] == 'result'
      return [unreadable, nil] if record['is_error'] || !turn?(record['session_id'])

      identity = record['session_id']
      [print_snapshot(identity, record), identity]
    end

    def print_snapshot(identity, record)
      { identity => { 'response_id' => identity, 'turn_id' => identity, 'timestamp' => record['timestamp'],
                      'aggregate' => true,
                      'configuration' => ['anthropic', 'UNKNOWN', print_model(record), record['effort']],
                      'billing_mode' => speed(record['usage']), 'usage' => tokens(record['usage']) } }
    end

    # Prefer a top-level model when a CLI writes one; otherwise one modelUsage canonical name.
    def print_model(record)
      present_name(record['model']) || present_name(canonical_model(record['modelUsage']))
    end

    def canonical_model(usage)
      return unless usage.is_a?(Hash) && usage.size == 1

      entry = usage.values.first
      entry['canonicalModel'] if entry.is_a?(Hash)
    end

    def present_name(value)
      value if value.is_a?(String) && !value.strip.empty?
    end

    def read(file)
      File.open(file, encoding: 'UTF-8') do |io|
        first = io.gets
        return [unreadable, nil] unless first
        return print_pretty(first, io) if first.strip == '{'

        record = parse(first)
        return finish_print(record, first, io) if record['type'] == 'result'

        jsonl_from(record, io)
      end
    rescue SystemCallError, EncodingError
      [unreadable, nil]
    end

    def print_pretty(first, io)
      print_object(JSON.parse(first + io.read.to_s)) || [unreadable, nil]
    rescue JSON::ParserError, EncodingError
      [unreadable, nil]
    end

    def finish_print(record, _first, io)
      rest = io.read.to_s
      return [unreadable, nil] unless rest.strip.empty?

      print_object(record) || [unreadable, nil]
    end

    def jsonl_from(record, io)
      records = {}
      turn = nil
      ingest = lambda do |item|
        turn = item['promptId'] if item['type'] == 'user'
        records.merge!(response(item, turn)) if item['type'] == 'assistant'
      end
      ingest.call(record)
      io.each { |line| ingest.call(parse(line)) }
      [records, turn]
    end
  end

  # Reads Claude Code session transcripts (tested with 2.1.270 and 2.1.272), keeping only usage metadata.
  class ClaudeUsage
    include ResponseCount
    include ClaudePrintResult

    HOST = 'Claude Code'
    NOTE = 'Anthropic input excludes cached input and cache writes; reasoning output is part of output.'
    LATEST_SCOPE = 'latest turn of the session, including its subagents; earlier turns excluded'
    INCLUSIVE_INPUT = false

    attr_reader :responses, :versions, :gaps

    def self.discover
      identity = ENV.fetch('CLAUDE_CODE_SESSION_ID', nil)
      return [] unless identity&.match?(/\A[0-9a-f-]{36}\z/)

      home = ENV.fetch('CLAUDE_CONFIG_DIR', File.expand_path('~/.claude'))
      sessions = Dir.glob(File.join(home, 'projects', '*', "#{identity}.jsonl"))
      return [] unless sessions.one? && session_of(sessions.first) == identity

      sessions + Dir.glob(File.join(File.dirname(sessions.first), identity, 'subagents', '*.jsonl'))
    end

    def self.session_of(file)
      File.foreach(file, encoding: 'UTF-8') do |line|
        record = JSON.parse(line)
        return record['sessionId'] if record.is_a?(Hash) && record.key?('sessionId')
      rescue JSON::ParserError, EncodingError
        next
      end
      nil
    rescue SystemCallError
      nil
    end

    private_class_method :session_of

    def initialize(files, turns, all_turns: false)
      @responses = {}
      @versions = []
      @gaps = []
      sources = files.map { |file| read(file) }
      count_selected(sources, turns, all_turns)
    end

    private

    def response(record, turn)
      message = record['message'].is_a?(Hash) ? record['message'] : {}
      @versions << record['version'] if record['version'].is_a?(String)
      { message['id'] => { 'response_id' => message['id'], 'turn_id' => turn, 'timestamp' => record['timestamp'],
                           'configuration' => ['anthropic', 'UNKNOWN', message['model'], record['effort']],
                           'billing_mode' => speed(message['usage']),
                           'usage' => tokens(message['usage']) } }
    end

    # Fast mode is billed at its own rates, so an unrecognized speed must not price as standard.
    def speed(usage)
      recorded = usage['speed'] if usage.is_a?(Hash)
      %w[standard fast].include?(recorded) ? recorded : 'UNKNOWN'
    end

    def tokens(usage)
      return {} unless usage.is_a?(Hash)

      { 'input_tokens' => usage['input_tokens'], 'cached_input_tokens' => usage['cache_read_input_tokens'],
        'output_tokens' => usage['output_tokens'], 'cache_write_input_tokens' => usage['cache_creation_input_tokens'],
        'cache_write_5m_input_tokens' => nested(usage, 'cache_creation', 'ephemeral_5m_input_tokens'),
        'cache_write_1h_input_tokens' => nested(usage, 'cache_creation', 'ephemeral_1h_input_tokens'),
        'reasoning_output_tokens' => nested(usage, 'output_tokens_details', 'thinking_tokens'),
        'web_search_requests' => server_tool_requests(usage, 'web_search_requests'),
        'inference_geo' => usage['inference_geo'] }
    end

    # A response that used no server tool omits the group or the counter, which is no charge.
    # A group that is present but unreadable is a gap, so it stays nil for the estimate to refuse.
    def server_tool_requests(usage, field)
      return 0 unless usage.key?('server_tool_use')

      recorded = usage['server_tool_use']
      return unless recorded.is_a?(Hash)

      recorded.key?(field) ? recorded[field] : 0
    end

    def nested(usage, group, field)
      recorded = usage[group]
      recorded[field] if recorded.is_a?(Hash)
    end

    def parse(line)
      record = JSON.parse(line)
      record.is_a?(Hash) ? record : unreadable
    rescue JSON::ParserError, EncodingError
      unreadable
    end

    def unreadable
      @gaps << 'Unreadable or unidentifiable records'
      {}
    end
  end
end
