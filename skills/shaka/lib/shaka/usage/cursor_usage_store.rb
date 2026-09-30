# frozen_string_literal: true

require 'fileutils'
require 'json'

module Shaka
  # Persists allowlisted Cursor stop-hook usage; never writes transcripts or emails.
  class CursorUsageStore
    IDENTITY = /\A[0-9a-f-]{36}\z/

    def self.discover
      identity = ENV.fetch('CURSOR_CONVERSATION_ID', nil)
      return [] unless identity&.match?(IDENTITY)

      file = File.join(home, "#{identity}.jsonl")
      File.file?(file) ? [file] : []
    end

    def self.home
      ENV.fetch('CURSOR_USAGE_DIR', File.expand_path('~/.cursor/shaka-usage'))
    end

    def self.persist(raw)
      record = compact(parse(raw))
      return 0 unless record

      FileUtils.mkdir_p(home)
      File.open(File.join(home, "#{record['conversation_id']}.jsonl"), 'a') do |file|
        file.flock(File::LOCK_EX)
        file.write("#{JSON.generate(record)}\n")
      end
      0
    rescue SystemCallError
      0
    end

    def self.parse(raw)
      record = JSON.parse(raw.to_s)
      record.is_a?(Hash) ? record : nil
    rescue JSON::ParserError, EncodingError
      nil
    end

    def self.compact(payload)
      return unless payload.is_a?(Hash) && payload['hook_event_name'] == 'stop'
      return unless payload['conversation_id'].to_s.match?(IDENTITY)
      return unless payload['generation_id'].to_s.match?(IDENTITY)

      payload.slice('conversation_id', 'generation_id', 'cursor_version', 'model', 'model_id', 'model_params',
                    'input_tokens', 'output_tokens', 'cache_read_tokens', 'cache_write_tokens')
             .merge('hook_event_name' => 'stop', 'timestamp' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
    end

    private_class_method :parse, :compact
  end
end
