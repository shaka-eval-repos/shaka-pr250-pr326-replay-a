# frozen_string_literal: true

require 'json'
require 'time'
require 'tmpdir'
require_relative 'response_count'

module Shaka
  # Reads OpenCode session exports (tested with 1.18.31), keeping only usage metadata.
  class OpencodeUsage
    include ResponseCount

    HOST = 'OpenCode'
    NOTE = 'Input excludes cache reads and writes; native total sums input, output, reasoning, and cache.'
    LATEST_SCOPE = 'latest user turn of the session, including its assistant responses; earlier turns excluded'
    SESSION = /\Ases_[A-Za-z0-9]+\z/
    INCLUSIVE_INPUT = false

    attr_reader :responses, :versions, :gaps

    # OpenCode 1.18.31 exports no session identifier into the tool environment, so this
    # finds a session only when a wrapper or plugin sets one; otherwise pass --session ID.
    def self.discover
      identity = ENV.fetch('OPENCODE_SESSION_ID', nil)
      identity.is_a?(String) && identity.match?(SESSION) ? ["session:#{identity}"] : []
    end

    def initialize(files, turns, all_turns: false)
      @responses = {}
      @versions = []
      @gaps = []
      unreadable('Pass an OpenCode session with --session ID.') if files.empty?
      live, stored = files.partition { |file| file.start_with?('session:') }
      sources = stored.map { |file| read_file(file) } + live.map { |entry| export(entry.delete_prefix('session:')) }
      count_selected(sources, turns, all_turns)
    end

    private

    # `opencode export` truncates its JSON when stdout is a pipe, so redirect to a
    # file first. capture3 cannot take an `out:` redirect, hence system with an
    # argument vector instead of shell interpolation.
    def export(session)
      unless session.is_a?(String) && session.match?(SESSION)
        return [unreadable('Pass an OpenCode session with --session ID.'), nil]
      end

      document = run_export(session)
      return [unreadable('OpenCode export failed for the selected session.'), nil] if document.nil?

      extract(document)
    rescue SystemCallError
      [unreadable('OpenCode export is unavailable.'), nil]
    end

    def run_export(session)
      Dir.mktmpdir('shaka-opencode-export') do |directory|
        target = File.join(directory, 'export.json')
        return nil unless system('opencode', 'export', session, out: target, err: File::NULL)

        parse(File.read(target, encoding: 'UTF-8'))
      end
    end

    def read_file(file)
      extract(parse(File.read(file, encoding: 'UTF-8')))
    rescue SystemCallError
      [unreadable, nil]
    end

    # Parts carry transcript text and are never read; only message info holds usage.
    def extract(document)
      messages = document['messages'] if document.is_a?(Hash)
      return [unreadable, nil] unless messages.is_a?(Array)

      info = document['info']
      @versions << info['version'] if info.is_a?(Hash) && info['version'].is_a?(String)
      [assistant_records(messages, configured_model(info)), latest_turn(messages)]
    end

    def configured_model(info)
      model = info['model'] if info.is_a?(Hash)
      model['id'] if model.is_a?(Hash)
    end

    def assistant_records(messages, configured)
      messages.each_with_object({}) do |message, records|
        info = message.is_a?(Hash) ? message['info'] : nil
        record = response(info, configured) if info.is_a?(Hash)
        records[record['response_id']] = record if record
      end
    end

    def latest_turn(messages)
      messages.filter_map { |message| user_turn(message) }.max_by(&:last)&.first
    end

    def user_turn(message)
      info = message.is_a?(Hash) ? message['info'] : nil
      return unless info.is_a?(Hash) && info['role'] == 'user' && turn?(info['id'])

      [info['id'], created_at(info)]
    end

    def created_at(info)
      created = info.dig('time', 'created')
      created.is_a?(Integer) && created >= 0 ? created : -1
    end

    def response(info, configured)
      return unless info['role'] == 'assistant'

      { 'response_id' => info['id'], 'turn_id' => info['parentID'],
        'timestamp' => iso(info.dig('time', 'completed') || info.dig('time', 'created')),
        'configuration' => [info['providerID'], configured, info['modelID'], info['variant']],
        'usage' => token_usage(info['tokens']) }
    end

    def token_usage(tokens)
      tokens = {} unless tokens.is_a?(Hash)
      cache = tokens['cache'].is_a?(Hash) ? tokens['cache'] : {}
      { 'input_tokens' => tokens['input'], 'cached_input_tokens' => cache['read'],
        'output_tokens' => tokens['output'], 'cache_write_input_tokens' => cache['write'],
        'reasoning_output_tokens' => tokens['reasoning'], 'total_tokens' => tokens['total'] }
    end

    def iso(millis)
      Time.at(Rational(millis, 1000)).utc.iso8601(3) if millis.is_a?(Integer) && millis >= 0
    end

    def parse(raw)
      record = JSON.parse(raw.to_s)
      record.is_a?(Hash) ? record : unreadable
    rescue JSON::ParserError, EncodingError
      unreadable
    end

    def unreadable(reason = 'Unreadable or unidentifiable records')
      @gaps << reason
      {}
    end
  end
end
