# frozen_string_literal: true

require_relative 'usage_cost_test'

# A few unpriceable responses must not hide the price of every other response in the column.
class UsagePartialCostTest < Minitest::Test
  include AnthropicCostFixture

  def contradictory
    anthropic_record.tap { |record| record['usage']['cache_write_5m_input_tokens'] = 1 }
  end

  def partial(*records)
    Shaka::CostEstimate.new(records, inclusive_input: false).report
  end

  # Break: three of 165 Claude responses with a contradictory cache-write split made the
  # whole Opus column UNKNOWN (PR #289, and the #269 evidence quoted in #287).
  def test_priced_responses_keep_their_estimate_marked_partial
    report = partial(anthropic_record, contradictory)
    assert_metric report, 'USD estimate', '$0.001110 (partial)'
    assert_includes report, 'Partial estimate: 1 of 2 responses unpriced (Inconsistent token subsets).'
  end

  def test_a_column_with_no_priced_response_stays_unknown
    report = partial(contradictory, contradictory)
    assert_metric report, 'USD estimate', 'UNKNOWN'
    refute_includes report, 'Partial estimate'
  end

  def test_a_fully_priced_column_is_not_marked_partial
    report = partial(anthropic_record, anthropic_record)
    assert_metric report, 'USD estimate', '$0.002220'
    refute_includes report, 'partial'
  end

  def test_openai_estimates_follow_the_same_rule
    setting = %w[openai gpt-5.6-terra UNKNOWN medium]
    usage = { 'input_tokens' => 100, 'cached_input_tokens' => 0, 'cache_write_input_tokens' => 0,
              'output_tokens' => 0 }
    priced = { 'configuration' => setting, 'usage' => usage }
    impossible = { 'configuration' => setting, 'usage' => usage.merge('cached_input_tokens' => 200) }
    report = Shaka::CostEstimate.new([priced, impossible]).report
    assert_metric report, 'USD estimate', '$0.000200 (partial)'
    assert_includes report, 'Partial estimate: 1 of 2 responses unpriced (Inconsistent token subsets).'
  end
end
