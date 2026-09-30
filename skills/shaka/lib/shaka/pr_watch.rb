# frozen_string_literal: true

require_relative 'error'
require_relative 'ci_review_wait'
require_relative 'pr_watch/review_gate'
require_relative 'public_comments'
require_relative 'status'

module Shaka
  # Polls one PR head without agent turns and exits when the owner has work to do.
  class PrWatch
    include ReviewGate

    DEFAULT_INTERVAL = 60
    DEFAULT_TIMEOUT = 3600
    DEFAULT_SETTLE = 15
    TERMINAL_BUCKETS = %w[pass fail skipping cancel].freeze
    PENDING_STATES = %w[PENDING QUEUED IN_PROGRESS].freeze
    COMMENT_KINDS = %w[issue_comments review_summaries inline_comments].freeze

    def initialize(github, head:, ci_jobs:, settings: {}, adapters: {})
      validate_head!(head)
      @github = github
      @head = head
      @ci_jobs = ci_jobs
      @ci_wait = CiReviewWait.normalize(settings[:ci_review_wait])
      @timing = timing(settings)
      @baseline = settings[:baseline]
      configure_adapters(adapters)
      @status = Status.new(github, seam_required_checks: settings[:seam_required_checks])
    end

    def call
      opening = opening_reason
      return opening if opening

      @seen = comment_ids(@baseline || @comments.call)
      wait_until(@clock.call + @timing.fetch(:timeout))
    end

    private

    def opening_reason
      opening = @github.snapshot
      return 'head_moved' if opening['headRefOid'] != @head

      'closed' unless opening['state'] == 'OPEN'
    end

    def wait_until(deadline)
      loop do
        result = observe
        return result if result
        return @pending_reason if settled?
        return @pending_reason || 'timeout' if @clock.call >= deadline

        next_poll = [@timing.fetch(:interval), deadline - @clock.call].min
        next_poll = [next_poll, @ready_since + @timing.fetch(:settle) - @clock.call].min if @pending_reason
        @sleeper.call([next_poll, 0].max)
      end
    end

    def validate_head!(head)
      raise Error, 'Expected a full PR head.' unless head.is_a?(String) && head.match?(/\A[0-9a-f]{40}\z/)
    end

    def timing(settings)
      values = { interval: DEFAULT_INTERVAL, timeout: DEFAULT_TIMEOUT, settle: DEFAULT_SETTLE }
               .merge(settings.slice(:interval, :timeout, :settle))
      valid = values.values.all? { |value| value.is_a?(Integer) && value.positive? }
      raise Error, 'Watch timing must be positive.' unless valid

      values
    end

    def configure_adapters(adapters)
      @clock = adapters.fetch(:clock) { -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) } }
      @sleeper = adapters.fetch(:sleeper) { ->(seconds) { sleep(seconds) } }
      @comments = adapters.fetch(:comments) { -> { PublicComments::Reader.new(@github).call(expected_head: @head) } }
    end

    def observe
      snapshot = @status.call
      return 'head_moved' if snapshot['headRefOid'] != @head
      return 'closed' unless snapshot['state'] == 'OPEN'
      raise Error, snapshot['requiredChecksUnavailable'] if snapshot['requiredChecksUnavailable']

      checks = @github.checks
      return 'head_moved' if @github.snapshot['headRefOid'] != @head

      update_pending(new_comments?, terminal_checks?(snapshot['requiredChecks'], checks))
      nil
    end

    def new_comments?
      ids = comment_ids(@comments.call)
      fresh = ids - @seen
      @seen |= ids
      fresh.any?
    end

    def terminal_checks?(required, checks)
      return false if required.empty? && (@ci_jobs.empty? || @ci_wait == 'none')

      terminal?(required) && review_jobs_terminal?(checks)
    end

    def update_pending(new_comments, terminal)
      if new_comments
        @pending_reason = 'trusted_comment'
        @ready_since = @clock.call
      elsif terminal && @pending_reason.nil?
        @pending_reason = 'checks_terminal'
        @ready_since = @clock.call
      elsif !terminal && @pending_reason == 'checks_terminal'
        @pending_reason = @ready_since = nil
      end
    end

    def settled? = @pending_reason && @clock.call - @ready_since >= @timing.fetch(:settle)

    def terminal?(rows)
      rows.is_a?(Array) && rows.all? do |row|
        row.is_a?(Hash) && TERMINAL_BUCKETS.include?(row['bucket']) && !PENDING_STATES.include?(row['state'])
      end
    end

    def comment_ids(packet)
      COMMENT_KINDS.flat_map { |kind| packet.fetch(kind).map { |row| [kind, row.fetch('id')] } }.uniq
    rescue NoMethodError, TypeError, KeyError
      raise Error, 'Malformed comment packet.'
    end
  end
end
