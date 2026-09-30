# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative '../error'
require_relative 'evidence'
require_relative 'finding'
require_relative 'ledger_storage'
require_relative 'ledger_guards'

module Shaka
  # One private ledger, with contiguous batches of reviews against the same head.
  class LocalReviewLedger
    include LocalReviewLedgerStorage
    include LocalReviewLedgerGuards

    attr_reader :path

    def initialize(path, root: nil)
      @path = File.expand_path(path)
      directory = File.realpath(File.dirname(@path))
      raise Error, '--ledger must be outside the candidate checkout' if
        root && (directory == root || directory.start_with?("#{root}/"))
    end

    def rounds = data.fetch('rounds')

    def last_round_fixes(reviewed_head = last_head)
      rounds.select { |round| round['head'] == reviewed_head }.flat_map do |round|
        LocalReviewFinding.list(round['findings'], 'batch finding').select(&:fixed?).map(&:commit)
      end.uniq
    end

    def last_head = rounds.last&.fetch('head')

    def prior_head(head) = rounds.reverse.find { |round| round['head'] != head }&.fetch('head')

    def check_next!(base:, head:, reviewer: nil)
      raise Error, "The ledger's rounds measure the change against #{data['base']}; use a new ledger." if
        data['base'] && data['base'] != base

      check_pending!(head, reviewer)
      return if rounds.empty?

      check_new_head!(head, reviewer)
      return if head == last_head

      check_dispositions!
    end

    # Reserve before launching; a peer still running prevents a new head from starting.
    def start!(base:, head:, reviewer:)
      locked do
        check_next!(base:, head:, reviewer:)
        @reservation = SecureRandom.hex(16)
        pending = data.fetch('pending', []) + [{ 'head' => head, 'reviewer' => reviewer, 'token' => @reservation }]
        write(data.merge('base' => base, 'pending' => pending))
      end
    end

    def cancel!
      return unless @reservation

      locked { write(data.merge('pending' => pending_without_reservation)) }
      @reservation = nil
    end

    # Current-head reports never enter a peer's prompt. Keep colliding reviewer finding IDs distinct.
    def prior_findings(head: nil)
      rounds.reject { |round| round['head'] == head }.each_with_index.with_object({}) do |(round, index), latest|
        LocalReviewFinding.list(round['findings'], "round #{index + 1} finding").each do |finding|
          latest[[round['reviewer'].downcase, finding.id]] = finding
        end
      end.values
    end

    def append!(base:, round:)
      snapshot = data
      locked do
        check_reservation!
        check_snapshot!(snapshot, round.fetch('head'))
        check_next!(base:, head: round.fetch('head'), reviewer: round.fetch('reviewer'))
        write(data.merge('base' => base, 'rounds' => rounds + [round], 'pending' => pending_without_reservation))
        @reservation = nil
        rounds.size
      end
    end

    # A numbered round keeps concurrent peer appends from redirecting a disposition.
    def record!(content, number: nil)
      raise Error, 'Record content must be an object.' unless content.is_a?(Hash)

      snapshot = data
      index = (number || rounds.size) - 1
      original = rounds[index] || raise(Error, 'The ledger has no round to record.')
      locked { update_record!(content, snapshot, original, index) }
    end

    private

    def update_record!(content, snapshot, original, index)
      check_record_snapshot!(snapshot, original, index)

      round = original.merge(content.slice('findings', 'model', 'tokens', 'cost', 'estimate'))
      check_findings!(round, index + 1)
      updated = rounds.dup
      updated[index] = round
      write(data.merge(content.slice('fallback'), 'rounds' => updated))
      index + 1
    end
  end
end
