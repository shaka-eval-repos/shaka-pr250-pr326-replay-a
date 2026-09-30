# frozen_string_literal: true

require 'json'

module Shaka
  # Refuses explicit turns that name nothing in a source that has readable turns.
  module UsageTurns
    FIELDS = { 'codex' => 'turn_id', 'claude-code' => 'promptId (session_id for claude -p JSON)',
               'cursor' => 'generation_id', 'opencode' => 'user message id', 'pi' => 'user entry id' }.freeze

    # A mistyped turn would otherwise publish an empty table that reads as missing records.
    # A source with no readable turns keeps its own unavailable-records report instead.
    def print_report
      missing = unmatched_turns
      if missing.empty?
        puts @options[:format] == 'json' ? JSON.pretty_generate(json_document) : report
        return 0
      end

      warn "shaka usage: --turn #{missing.join(', ')} matched no readable response; " \
           "#{@options[:host]} turns use the #{FIELDS.fetch(@options[:host])} field"
      1
    end

    private

    def unmatched_turns
      @source.readable_turns? ? @options[:turns].uniq - @source.matched_turns : []
    end
  end
end
