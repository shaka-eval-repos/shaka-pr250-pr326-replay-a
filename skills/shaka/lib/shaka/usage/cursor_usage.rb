# frozen_string_literal: true

require 'json'
require_relative 'cursor_usage_store'
require_relative 'response_count'

module Shaka
  # Reads effort and Fast/standard billing flags from Cursor model_params.
  module CursorParams
    private

    def effort(params)
      param(params, 'effort') || param(params, 'reasoning_effort')
    end

    def billing_mode(params)
      value = param(params, 'fast')
      if [true, 'true'].include?(value)
        'fast'
      elsif [false, 'false'].include?(value)
        'standard'
      end
    end

    def param(params, id)
      found = params.find { |item| item.is_a?(Hash) && item['id'] == id } if params.is_a?(Array)
      found['value'] if found
    end
  end

  # Reads persisted Cursor stop-hook usage; transcripts and bubble tokenCount are unused.
  class CursorUsage
    include ResponseCount
    include CursorParams

    HOST = 'Cursor'
    NOTE = 'Cached input and cache writes are part of input; reasoning output and native total are UNKNOWN. ' \
           'Parent-agent turn only; subagents excluded.'
    LATEST_SCOPE = 'latest generation only per source; earlier turns excluded'
    EVENTS = %w[stop afterAgentResponse].freeze
    UNAVAILABLE = 'usage reader unavailable: no readable Cursor stop-hook records'

    attr_reader :responses, :versions, :gaps

    def self.discover
      CursorUsageStore.discover
    end

    def self.persist(raw)
      CursorUsageStore.persist(raw)
    end

    def initialize(files, turns, all_turns: false)
      @responses = {}
      @versions = []
      @gaps = []
      files.each { |file| ingest(file, turns, all_turns) }
      @gaps << UNAVAILABLE unless readable_turns?
    end

    def context_configuration
      ['cursor', present(ENV.fetch('CURSOR_MODEL_ID', nil)), present(ENV.fetch('CURSOR_MODEL', nil)),
       present(ENV.fetch('CURSOR_MODEL_EFFORT', nil))]
    end

    private

    def ingest(file, turns, all_turns)
      chosen, last = read(file)
      wanted = selected_turns(chosen, last, turns, all_turns)
      keep_selected(chosen, wanted, all_turns)
    end

    def keep_selected(chosen, wanted, all_turns)
      identified = chosen.values.select { |record| turn?(record['turn_id']) }
      note_readable(identified)
      unreadable if all_turns && identified.size < chosen.values.size
      identified.each { |record| count(record.except('preferred')) if wanted.include?(record['turn_id']) }
    end

    def present(value)
      value if value.is_a?(String) && !value.strip.empty?
    end

    def selected_turns(chosen, last, turns, all_turns)
      ids = if all_turns
              chosen.keys
            elsif turns.empty?
              [last]
            else
              turns
            end
      ids.select { |turn| turn?(turn) }
    end

    def turn?(turn)
      turn.is_a?(String) && !turn.strip.empty?
    end

    def read(file)
      chosen = {}
      last = nil
      File.foreach(file, encoding: 'UTF-8') { |line| last = keep(chosen, response(parse(line))) || last }
      [chosen, last]
    rescue SystemCallError
      [unreadable, nil]
    end

    def keep(chosen, record)
      return unless record

      identity = record['response_id']
      chosen[identity] = record if chosen[identity].nil? || record['preferred']
      identity
    end

    def response(payload)
      return unless payload.is_a?(Hash) && EVENTS.include?(payload['hook_event_name'])

      @versions << payload['cursor_version'] if payload['cursor_version'].is_a?(String)
      record(payload)
    end

    def record(payload)
      { 'response_id' => payload['generation_id'], 'turn_id' => payload['generation_id'],
        'timestamp' => payload['timestamp'], 'preferred' => payload['hook_event_name'] == 'stop',
        'configuration' => configuration(payload), 'billing_mode' => billing_mode(payload['model_params']),
        'usage' => tokens(payload) }
    end

    def configuration(payload)
      ['cursor', payload['model_id'], payload['model'], effort(payload['model_params'])]
    end

    def tokens(payload)
      { 'input_tokens' => payload['input_tokens'], 'cached_input_tokens' => payload['cache_read_tokens'],
        'output_tokens' => payload['output_tokens'], 'cache_write_input_tokens' => payload['cache_write_tokens'] }
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
