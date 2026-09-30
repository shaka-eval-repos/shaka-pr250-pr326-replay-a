# frozen_string_literal: true

require_relative 'error'

module Shaka
  # Size limits past which an agent merge needs a human to confirm the exact head.
  class MergeLimits
    # Inclusive maxima: the next value needs confirmation.
    DEFAULTS = { 'max_changed_files' => 29, 'max_changed_lines' => 999, 'max_commits' => 9 }.freeze

    def self.validate!(limits)
      raise Error, 'merge.limits must be a mapping' unless limits.is_a?(Hash) && limits.keys.all?(String)

      unknown = limits.keys - DEFAULTS.keys
      raise Error, "unknown merge.limits key: #{unknown.first}" unless unknown.empty?

      limits.each do |key, value|
        raise Error, "merge.limits.#{key} must be a positive integer" unless value.is_a?(Integer) && value.positive?
      end
    end

    def self.from_ref(root:, ref:, confirmed_head: nil)
      return new(confirmed_head:) unless ref

      require_relative 'configuration'
      new(Configuration.trusted(root:, ref:).merge.fetch('limits'), confirmed_head:)
    end

    # confirmed_head names the head a user approved past these limits; any other head needs a new decision.
    def initialize(limits = {}, confirmed_head: nil)
      self.class.validate!(limits)
      @limits = DEFAULTS.merge(limits)
      @confirmed_head = confirmed_head
    end

    def to_h
      @limits.dup
    end

    def verify!(pull, head)
      return verify_confirmation!(head) if @confirmed_head

      exceeded = counts(pull).filter_map do |key, count|
        "#{key.delete_prefix('max_')} #{count} > #{@limits.fetch(key)}" if count > @limits.fetch(key)
      end
      return if exceeded.empty?

      raise Error, "PR exceeds merge limits (#{exceeded.join(', ')}); hand it to the user as Ask, " \
                   'or pass --limits-confirmed-head for a head the user confirmed'
    end

    private

    def verify_confirmation!(head)
      return if @confirmed_head == head

      raise Error, "Limit confirmation names #{@confirmed_head}, not the current head #{head}; " \
                   'ask the user to confirm this head'
    end

    def counts(pull)
      commits = pull['commits']
      counts = {
        'max_changed_files' => pull['changedFiles'],
        'max_changed_lines' => sum(pull['additions'], pull['deletions']),
        'max_commits' => commits.is_a?(Hash) ? commits['totalCount'] : nil
      }
      return counts if counts.values.all? { |count| count.is_a?(Integer) && count >= 0 }

      raise Error, 'GitHub did not report the PR size; merge limits cannot be checked, so hand it to ' \
                   'the user as Ask or pass --limits-confirmed-head for a head the user confirmed'
    end

    def sum(additions, deletions)
      additions + deletions if additions.is_a?(Integer) && deletions.is_a?(Integer)
    end
  end
end
