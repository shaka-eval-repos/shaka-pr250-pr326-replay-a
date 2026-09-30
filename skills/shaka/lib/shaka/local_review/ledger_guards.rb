# frozen_string_literal: true

module Shaka
  # Preserve batch identity, dispositions, and optimistic snapshots under the write lock.
  module LocalReviewLedgerGuards
    private

    def check_reservation!
      return unless @reservation
      return if data.fetch('pending', []).any? { |entry| entry['token'] == @reservation }

      raise Error, 'Stale ledger: the pending review reservation disappeared.'
    end

    def check_record_snapshot!(snapshot, original, index)
      return if data['base'] == snapshot['base'] && rounds[index] == original

      raise Error, 'Stale ledger: the selected round changed; read it again.'
    end

    def check_dispositions!
      rounds.each_with_index do |round, index|
        next if recorded?(round)

        raise Error, "Record round #{index + 1}'s findings with `shaka review record` before the next round."
      end
    end

    def check_pending!(head, reviewer)
      data.fetch('pending', []).each do |entry|
        next if entry['token'] == @reservation

        raise Error, 'Finish the pending review batch before reviewing another head.' if entry['head'] != head
        raise Error, 'This reviewer already has a pending review of this head.' if
          reviewer && entry['reviewer'].casecmp?(reviewer)
      end
    end

    def check_snapshot!(snapshot, head)
      stable = snapshot.fetch('rounds').each_with_index.all? { |round, index| unchanged?(round, rounds[index], head) }
      raise Error, 'Stale ledger: earlier review evidence changed; read it again.' unless
        stable && (!snapshot['base'] || snapshot['base'] == data['base'])
    end

    def unchanged?(round, current, head)
      return current == round unless round['head'] == head

      fields = %w[findings model tokens cost estimate]
      current && current.except(*fields) == round.except(*fields)
    end

    def check_new_head!(head, reviewer)
      reviewed = rounds.index do |round|
        round['head'] == head && (head != last_head || !reviewer || round['reviewer'].casecmp?(reviewer))
      end
      raise Error, "Round #{reviewed + 1} already reviewed #{head}; commit the fix first." if reviewed
    end

    def recorded?(round) = round.key?('findings') || reported_count(round).zero?

    def check_findings!(round, number)
      findings = LocalReviewFinding.list(round['findings'], "round #{number} finding")
      reported = reported_count(round)
      return if findings.size == reported

      raise Error, "Round #{number}'s report counts #{reported} findings; #{findings.size} were recorded."
    end

    def reported_count(round)
      match = File.read(round.fetch('report'), encoding: 'UTF-8').match(LocalReviewEvidence::CLOSING)
      raise Error, "Round report #{round['report']} has no FINDINGS count." unless match

      match[2].to_i
    end
  end
end
