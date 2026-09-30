# frozen_string_literal: true

module Shaka
  # Counts each native response once across sources; conflicting copies keep no usage.
  module ResponseCount
    # Whether a reader's input counter already contains its cached and written subsets,
    # as the OpenAI and Cursor rates in the cost estimator assume. A reader that reports
    # them separately is priced only where the estimator publishes exclusive rates.
    INCLUSIVE_INPUT = true

    # Turns of the selected records, noted before conflicting copies lose their turn.
    def matched_turns = @matched_turns || []

    # Whether any source held an identified response in an identified turn, whatever was selected.
    def readable_turns? = @readable_turns || false

    private

    def note_readable(records)
      @readable_turns = readable_turns? || records.any? do |record|
        identity = record['response_id']
        turn?(record['turn_id']) && identity.is_a?(String) && !identity.empty?
      end
    end

    def count(record)
      identity = record['response_id']
      return @gaps << 'Unreadable or unidentifiable records' unless identity.is_a?(String) && !identity.empty?

      (@matched_turns ||= []) << record['turn_id']

      previous = @responses[identity]
      if previous && previous != record
        previous.merge!('usage' => {}, 'configuration' => [nil] * 4, 'timestamp' => nil, 'turn_id' => nil,
                        'billing_mode' => nil)
        @gaps << 'Conflicting response copies'
      end
      @responses[identity] ||= record
    end

    # Without explicit turns, every source uses the first source's latest turn.
    def count_selected(sources, turns, all_turns)
      records = sources.map(&:first).flat_map(&:values)
      note_readable(records)
      selected(records, wanted_turns(sources, turns), all_turns).each { |record| count(record) }
    end

    # Every mode needs an identified turn, as in the Codex reader.
    def selected(records, wanted, all_turns)
      identified = records.select { |record| turn?(record['turn_id']) }
      unreadable if all_turns && identified.size < records.size
      all_turns ? identified : identified.select { |record| wanted.include?(record['turn_id']) }
    end

    def wanted_turns(sources, turns)
      (turns.empty? ? [sources.dig(0, 1)] : turns).select { |turn| turn?(turn) }
    end

    def turn?(turn)
      turn.is_a?(String) && !turn.strip.empty?
    end
  end
end
