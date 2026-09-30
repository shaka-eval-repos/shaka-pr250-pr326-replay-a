# frozen_string_literal: true

require 'json'
require_relative '../error'
require_relative 'evidence'
require_relative 'finding'

module Shaka
  # Private record of a local review loop: each round's commit, reviewer settings, report, and
  # what became of its findings. It stays outside the checkout until `review publish` renders it,
  # and it has the same shape as that command's content file.
  class LocalReviewLedger
    attr_reader :path

    # Only `review run` can start a ledger, so only it needs the checkout to keep the ledger out of.
    def initialize(path, root: nil)
      @path = File.expand_path(path)
      directory = File.realpath(File.dirname(@path))
      raise Error, '--ledger must be outside the candidate checkout' if
        root && (directory == root || directory.start_with?("#{root}/"))
    end

    def rounds = data.fetch('rounds')

    def last_round_fixes
      LocalReviewFinding.list(rounds.last['findings'], "round #{rounds.size} finding").select(&:fixed?).map(&:commit)
    end

    def last_head = rounds.last&.fetch('head')

    # A round reviews a new commit on the same base, after the previous round's findings are recorded.
    def check_next!(base:, head:)
      return if rounds.empty?

      raise Error, "The ledger's rounds measure the change against #{data['base']}; use a new ledger." unless
        data['base'] == base

      check_new_head!(head)
      return if recorded?(rounds.last)

      raise Error, "Record round #{rounds.size}'s findings with `shaka review record` before the next round."
    end

    # The newest disposition of every finding so far, keyed by the id rounds share.
    def prior_findings
      rounds.each_with_index.with_object({}) do |(round, index), latest|
        LocalReviewFinding.list(round['findings'], "round #{index + 1} finding").each do |finding|
          latest[finding.id] = finding
        end
      end.values
    end

    def append!(base:, round:)
      write(data.merge('base' => base, 'rounds' => rounds + [round]))
    end

    # Sets the last round's findings and any usage the host reported for it.
    def record!(content)
      raise Error, 'Record content must be an object.' unless content.is_a?(Hash)

      round = last_round.merge(content.slice('findings', 'model', 'tokens', 'cost', 'estimate'))
      check_findings!(round, rounds.size)
      write(data.merge(content.slice('fallback'), 'rounds' => rounds[0...-1] + [round]))
    end

    private

    def data
      @data ||= if File.exist?(@path)
                  parsed = JSON.parse(File.read(@path, encoding: 'UTF-8'))
                  raise Error, "#{@path} is not a review ledger." unless
                    parsed.is_a?(Hash) && parsed['rounds'].is_a?(Array)

                  parsed
                else
                  { 'rounds' => [] }
                end
    end

    def last_round = rounds.last || raise(Error, 'The ledger has no round to record.')

    def check_new_head!(head)
      reviewed = rounds.index { |round| round['head'] == head }
      raise Error, "Round #{reviewed + 1} already reviewed #{head}; commit the fix first." if reviewed
    end

    def recorded?(round) = round.key?('findings') || reported_count(round).zero?

    # The count check keeps a finding from dropping out between the report and the comment.
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

    def write(content)
      temporary = "#{@path}.#{Process.pid}.tmp"
      File.write(temporary, "#{JSON.pretty_generate(content)}\n", perm: 0o600)
      File.rename(temporary, @path)
      @data = content
    end
  end
end
