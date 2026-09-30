# frozen_string_literal: true

require_relative 'error'

module Shaka
  # CI review waiting policy, ordered from least to most restrictive.
  class CiReviewWait
    VALUES = %w[none one all].freeze
    DEFAULT = 'one'

    def self.normalize(value)
      return DEFAULT if value.nil?

      raise Error, 'review.ci_review_wait must be none, one, or all' unless VALUES.include?(value)

      value
    end

    def self.effective(seam:, override: nil)
      return normalize(override) if seam.nil?

      waits = [normalize(seam)]
      waits << normalize(override) unless override.nil?
      waits.max_by { |wait| VALUES.index(wait) }
    end

    def self.allowed_merge_states(wait, queue_enabled)
      allow_unstable = normalize(wait) != 'all'
      return %w[CLEAN BEHIND BLOCKED UNSTABLE] if queue_enabled && allow_unstable
      return %w[CLEAN BEHIND BLOCKED] if queue_enabled
      return %w[CLEAN UNSTABLE] if allow_unstable

      %w[CLEAN]
    end
  end
end
