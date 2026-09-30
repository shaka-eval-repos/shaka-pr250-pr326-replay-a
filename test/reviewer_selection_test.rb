# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/reviewer_selection'

# Choosing which local reviewer to run first. A fresh context is what makes a review adversarial,
# so no identity disqualifies a reviewer and no input produces a blocker.
class ReviewerSelectionTest < Minitest::Test
  ROSTER = [{ 'provider' => 'anthropic', 'model_family' => 'claude' },
            { 'provider' => 'openai', 'model_family' => 'codex' },
            { 'provider' => 'xai', 'model_family' => 'grok' }].freeze

  def select(implementers, unavailable: [], reviewers: ROSTER)
    Shaka::ReviewerSelection.new(
      reviewers:,
      implementers: implementers.map { |text| Shaka::ReviewerSelection.parse(text) },
      unavailable: unavailable.map { |text| Shaka::ReviewerSelection.parse(text) }
    ).call
  end

  def test_prefers_a_provider_that_did_not_implement_the_change
    result = select(['anthropic/claude'])

    assert_equal 'different_provider', result.fetch('outcome')
    assert_equal 'openai/codex', result.fetch('reviewer')
  end

  # https://github.com/shakacode/shaka/pull/137 reviewed a Sol implementation with Astra.
  def test_openai_implementation_prefers_claude
    result = select(['openai/codex'])

    assert_equal 'different_provider', result.fetch('outcome')
    assert_equal 'anthropic/claude', result.fetch('reviewer')
  end

  def test_skips_an_unavailable_reviewer_for_the_next_provider
    result = select(['anthropic/claude'], unavailable: ['openai/codex'])

    assert_equal 'different_provider', result.fetch('outcome')
    assert_equal 'xai/grok', result.fetch('reviewer')
  end

  def test_uses_the_implementation_provider_when_no_other_is_available
    result = select(['anthropic/claude'], unavailable: %w[openai/codex xai/grok])

    assert_equal 'same_provider', result.fetch('outcome')
    assert_equal 'anthropic/claude', result.fetch('reviewer')
    assert_includes result.fetch('note'), 'context is still fresh'
  end

  # The implementation model in a fresh context is a review, not a failure.
  def test_falls_back_to_the_implementation_model_when_nothing_listed_is_available
    roster = [{ 'provider' => 'openai', 'model_family' => 'codex' },
              { 'provider' => 'xai', 'model_family' => 'grok' }]
    result = select(['anthropic/claude'], unavailable: %w[openai/codex xai/grok], reviewers: roster)

    assert_equal 'same_model', result.fetch('outcome')
    assert_equal 'anthropic/claude', result.fetch('reviewer')
    assert_includes result.fetch('note'), 'valid review'
  end

  def test_falls_back_to_the_implementation_model_when_the_seam_lists_none
    result = select(['openai/codex'], reviewers: nil)

    assert_equal 'same_model', result.fetch('outcome')
    assert_equal 'openai/codex', result.fetch('reviewer')
  end

  # A delegated worker's provider also implemented, so prefer one that did not.
  def test_counts_every_implementing_provider_when_preferring
    result = select(['anthropic/claude', 'openai/codex'])

    assert_equal 'xai/grok', result.fetch('reviewer')
  end

  def test_matches_an_unavailable_identity_regardless_of_casing
    result = select(['anthropic/claude'], unavailable: ['OpenAI/Codex'])

    assert_equal 'xai/grok', result.fetch('reviewer')
  end

  def test_reports_why_each_entry_was_or_was_not_chosen
    reasons = select(['anthropic/claude'], unavailable: ['openai/codex'])
              .fetch('considered').to_h { |row| [row.fetch('reviewer'), row.fetch('reason')] }

    assert_equal 'same provider as the implementation', reasons.fetch('anthropic/claude')
    assert_equal 'unavailable', reasons.fetch('openai/codex')
    assert_equal 'available', reasons.fetch('xai/grok')
  end

  # A fresh implementation-model context remains the fallback when every CLI path fails.
  def test_uses_same_model_when_even_the_implementer_cli_is_unavailable
    result = select(['anthropic/claude'],
                    unavailable: %w[anthropic/claude openai/codex xai/grok])

    assert_equal 'same_model', result.fetch('outcome')
    assert_equal 'anthropic/claude', result.fetch('reviewer')
    assert_includes result.fetch('note'), 'fresh context'
  end

  # With several implementers, the fallback must name one that can actually run.
  def test_names_an_available_implementer_for_the_same_model_fallback
    roster = [{ 'provider' => 'xai', 'model_family' => 'grok' }]
    result = select(['anthropic/claude', 'openai/codex'],
                    unavailable: %w[xai/grok anthropic/claude], reviewers: roster)

    assert_equal 'same_model', result.fetch('outcome')
    assert_equal 'openai/codex', result.fetch('reviewer')
  end

  def test_requires_at_least_one_implementer
    error = assert_raises(Shaka::Error) { select([]) }

    assert_includes error.message, 'implementer identity is required'
  end
end
