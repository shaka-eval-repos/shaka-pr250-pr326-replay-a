# frozen_string_literal: true

require 'json'
require_relative 'response_count'

module Shaka
  # Retains only usage metadata; transcripts and cumulative counters are discarded.
  class CodexUsage
    include ResponseCount

    HOST = 'Codex'
    NOTE = 'Cached input is part of input; reasoning output is part of output.'
    LATEST_SCOPE = 'latest turn only per source; earlier turns excluded'

    attr_reader :responses, :versions, :gaps

    def initialize(files, turns, all_turns: false)
      @responses = {}
      @all_turns = all_turns
      @versions = []
      @gaps = []
      files.each { |file| read(file, turns) }
    end

    def self.discover
      file = session_file(ENV.fetch('CODEX_THREAD_ID', nil))
      file ? [file] : []
    end

    # `codex exec --json` announces its thread first; that thread's saved session holds its token counts.
    def self.announced_session(events)
      events.each_line do |line|
        event = JSON.parse(line)
        return session_file(event['thread_id']) if event.is_a?(Hash) && event['type'] == 'thread.started'
      rescue JSON::ParserError, EncodingError
        next
      end
      nil
    end

    # The saved session for one thread ID, or nil when it is not exactly one matching file.
    def self.session_file(identity)
      return unless identity.is_a?(String) && identity.match?(/\A[0-9a-f-]{36}\z/)

      home = ENV.fetch('CODEX_HOME', File.expand_path('~/.codex'))
      files = Dir.glob(File.join(home, 'sessions', '*', '*', '*', "*#{identity}.jsonl"))
      return unless files.one?

      metadata = JSON.parse(File.open(files.first, encoding: 'UTF-8', &:readline))
      files.first if matching_source?(metadata, identity)
    rescue JSON::ParserError, EncodingError, SystemCallError, EOFError
      nil
    end

    def self.matching_source?(metadata, identity)
      metadata.is_a?(Hash) && metadata['type'] == 'session_meta' &&
        metadata['payload'].is_a?(Hash) && metadata['payload']['id'] == identity
    end

    private_class_method :matching_source?

    private

    def read(file, turns)
      @context = {}
      @provider = nil
      @records = []
      File.foreach(file, encoding: 'UTF-8') { |line| consume(parse(line)) }
      note_readable(@records)
      selected = selected_turns(turns)
      @gaps << 'Unreadable or unidentifiable records' if @all_turns && selected.size != @records.size
      @records.select { |record| selected.include?(record['turn_id']) }.each { |record| count(record) }
    rescue SystemCallError
      @gaps << 'Unreadable or unidentifiable records'
    end

    def selected_turns(turns)
      turns = @records.map { |record| record['turn_id'] } if @all_turns
      selected = turns.empty? ? [@context['turn_id']] : turns
      selected.grep(String).reject { |turn| turn.strip.empty? }
    end

    def consume(record)
      return unless record

      payload = record['payload']
      case record['type']
      when 'session_meta'
        @provider = payload['model_provider']
        @versions << payload['cli_version']
      when 'turn_context' then @context = payload.slice('turn_id', 'model', 'effort')
      when 'token_usage_record' then @records << response(record)
      end
    end

    def response(record)
      payload = record['payload']
      settings = payload['turn_id'] == @context['turn_id'] ? @context : {}
      payload.slice('response_id', 'turn_id', 'usage').merge(
        'timestamp' => record['timestamp'],
        'configuration' => [@provider, settings['model'], 'UNKNOWN', settings['effort']]
      )
    end

    def parse(line)
      record = JSON.parse(line) if line.valid_encoding?
      return record if record.is_a?(Hash) && record['payload'].is_a?(Hash)

      unreadable
    rescue JSON::ParserError, EncodingError
      unreadable
    end

    # An unreadable line may have changed the turn's settings, so later responses keep
    # the turn but not a model or effort that might no longer apply.
    def unreadable
      @gaps << 'Unreadable or unidentifiable records'
      @context = @context.slice('turn_id')
      nil
    end
  end
end
