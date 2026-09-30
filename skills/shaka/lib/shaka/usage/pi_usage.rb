# frozen_string_literal: true

require 'json'
require 'pathname'
require_relative 'response_count'

# Native Pi session usage reporting.
module Shaka
  # Maps Pi's disjoint counters and rejects contradictions.
  module PiCounters
    private

    def token_usage(usage)
      return unpriced_native unless usage.is_a?(Hash)

      tokens = { 'input_tokens' => usage['input'], 'cached_input_tokens' => usage['cacheRead'],
                 'output_tokens' => usage['output'], 'reasoning_output_tokens' => reasoning(usage),
                 'cache_write_input_tokens' => usage['cacheWrite'], 'total_tokens' => usage['totalTokens'],
                 'native_cost_usd' => native_cost(usage['cost']) }
      if invalid_reasoning?(tokens) || contradictory_total?(tokens)
        unreadable
        return unpriced_native
      end

      tokens
    end

    def reasoning(usage)
      value = usage['reasoning']
      value.nil? && usage['output'].eql?(0) ? 0 : value
    end

    def invalid_reasoning?(tokens)
      reasoning = tokens['reasoning_output_tokens']
      output = tokens['output_tokens']
      !reasoning.nil? && (!reasoning.is_a?(Integer) || reasoning.negative? ||
        !output.is_a?(Integer) || reasoning > output)
    end

    def contradictory_total?(tokens)
      categories = %w[input_tokens cached_input_tokens output_tokens cache_write_input_tokens]
                   .map { |field| tokens[field] }
      total = tokens['total_tokens']
      [*categories, total].all? { |value| value.is_a?(Integer) && value >= 0 } && categories.sum != total
    end

    def native_cost(cost)
      value = cost['total'] if cost.is_a?(Hash)
      is_number = value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      value if is_number && value >= 0
    end

    def unpriced_native
      { 'native_cost_usd' => nil }
    end
  end

  # Parses one Pi v3 session and extracts aggregate-safe active-branch records.
  class PiSession
    include PiCounters

    VERSION = 3

    attr_reader :source, :gaps, :version

    def self.header(file)
      JSON.parse(File.open(file, encoding: 'UTF-8', &:readline))
    rescue JSON::ParserError, EncodingError, SystemCallError, EOFError
      nil
    end

    def self.valid_header?(header)
      header.is_a?(Hash) && header['type'] == 'session' && header['version'] == VERSION && identity?(header['id'])
    end

    def self.identity?(value)
      value.is_a?(String) && !value.strip.empty?
    end

    def initialize(file)
      @gaps = []
      @source = read(file)
    end

    private

    def read(file)
      records = File.foreach(file, encoding: 'UTF-8').map { |line| JSON.parse(line) }
      header = records.shift
      return unavailable unless records.all?(Hash) && self.class.valid_header?(header)

      @version = VERSION.to_s
      entries = indexed(records)
      entries ? extract(branch(entries)) : unavailable
    rescue JSON::ParserError, EncodingError, SystemCallError, EOFError
      unavailable
    end

    def indexed(records)
      entries = {}
      is_valid = records.all? { |record| index(entries, record) }
      entries if is_valid && !entries.empty?
    end

    def index(entries, record)
      parent = record['parentId']
      is_valid = record['type'].is_a?(String) && identity?(record['id']) && !entries.key?(record['id']) &&
                 (parent.nil? || (identity?(parent) && entries.key?(parent)))
      entries[record['id']] = record if is_valid
      is_valid
    end

    def branch(entries)
      selected = []
      entry = entries.values.last
      while entry
        selected << entry
        entry = entries[entry['parentId']]
      end
      selected.reverse
    end

    def extract(entries)
      state = { effort: nil, turn: nil }
      records = {}
      entries.each { |entry| consume(records, state, entry) }
      [records, state[:turn]]
    end

    def consume(records, state, entry)
      case entry['type']
      when 'thinking_level_change' then state[:effort] = setting(entry['thinkingLevel'])
      when 'message' then consume_message(records, state, entry)
      when 'compaction', 'branch_summary'
        @gaps << 'Compaction/summary usage on active branch excluded' if entry['usage'].is_a?(Hash)
      end
    end

    def consume_message(records, state, entry)
      message = entry['message']
      return unreadable unless message.is_a?(Hash)

      state[:turn] = entry['id'] if message['role'] == 'user'
      return unless message['role'] == 'assistant'

      identity = identity?(message['responseId']) ? message['responseId'] : "#{entry['id']}:#{entry['timestamp']}"
      records[entry['id']] = response(identity, state, entry, message)
    end

    def response(identity, state, entry, message)
      { 'response_id' => identity, 'turn_id' => state[:turn], 'timestamp' => entry['timestamp'],
        'configuration' => [message['provider'], message['model'], message['responseModel'], state[:effort]],
        'usage' => token_usage(message['usage']) }
    end

    def setting(value)
      return value if identity?(value)

      unreadable
      nil
    end

    def identity?(value) = self.class.identity?(value)

    def unavailable
      unreadable
      [{}, nil]
    end

    def unreadable
      @gaps << 'Unreadable or unidentifiable records'
      {}
    end
  end

  # Selects responses from active Pi branches without retaining session content.
  class PiUsage
    include ResponseCount

    HOST = 'Pi'
    NOTE = 'Input excludes cache reads and writes; reasoning output is part of output. ' \
           'Recorded native cost is nominal, not an actual charge.'
    LATEST_SCOPE = 'latest user turn on the active branch; earlier turns and abandoned branches excluded'
    INCLUSIVE_INPUT = false

    attr_reader :responses, :versions, :gaps

    def self.discover
      identity = ENV.fetch('PI_SESSION_ID', nil)
      file = ENV.fetch('PI_SESSION_FILE', nil)
      return [] unless PiSession.identity?(identity) && file.is_a?(String) && Pathname.new(file).absolute?

      header = PiSession.header(file)
      PiSession.valid_header?(header) && header['id'] == identity ? [file] : []
    end

    def initialize(files, turns, all_turns: false)
      @responses = {}
      @versions = []
      @gaps = []
      unreadable if files.empty?
      count_selected(files.map { |file| load_session(file) }, turns, all_turns)
    end

    private

    def load_session(file)
      session = PiSession.new(file)
      @versions << session.version if session.version
      @gaps.concat(session.gaps)
      session.source
    end

    def unreadable
      @gaps << 'Unreadable or unidentifiable records'
      {}
    end
  end

  private_constant :PiCounters, :PiSession
end
