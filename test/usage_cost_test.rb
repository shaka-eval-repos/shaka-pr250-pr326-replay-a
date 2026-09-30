# frozen_string_literal: true

require_relative 'usage_test'
require_relative '../skills/shaka/lib/shaka/usage/cost_estimate'

class UsageCostTest < Minitest::Test
  include UsageFixture

  def test_estimates_configured_model_scenarios_without_double_counting_subsets
    setting = priced_context('current', 'gpt-5.6-terra', effort: 'medium')
    response = priced_usage('priced', 'current', 200_000, cached: 40_000, output: 20_000)
    response[:payload][:usage][:reasoning_output_tokens] = 4_000
    report = run_report([setting, response, response])
    assert_metric report, 'Credits estimate', '14.200000'
    assert_metric report, 'USD estimate', '$0.568000'
    assert_includes report, '1 responses'
    assert_openai_sources report, 'gpt-5.6-terra'
    refute_unrelated_cost_copy report, 'gpt-5.6-sol', 'gpt-6-astra'
    refute_includes report, '272K'
  end

  def test_cost_headers_prefer_model_when_effort_also_differs
    records = [priced_context('first', 'gpt-5.6-terra', effort: 'high'),
               priced_usage('first', 'first', 100, output: 0),
               priced_context('second', 'gpt-6-astra', effort: 'low'),
               priced_usage('second', 'second', 100, output: 0)]
    report = run_report(records, '--turn', 'first', '--turn', 'second')
    assert_metric report, 'Metric', 'gpt-5.6-terra', 'gpt-6-astra'
    refute_includes report, '| Metric | high | low |'
  end

  def test_api_estimate_prices_cache_writes_separately_and_credit_estimate_stays_unknown
    setting = priced_context('current', 'gpt-5.6-terra')
    response = priced_usage('priced', 'current', 200_000, cached: 40_000, writes: 20_000, output: 20_000)
    report = run_report([setting, response])
    assert_metric report, 'Credits estimate', 'UNKNOWN'
    assert_metric report, 'USD estimate', '$0.578000'
    assert_includes report, 'Credit cache-write rate UNKNOWN'
  end

  def test_model_switches_and_large_context_are_priced_per_response
    records = [priced_context('first', 'gpt-5.6-terra'),
               priced_usage('first', 'first', 100, output: 0),
               priced_context('second', 'gpt-6-astra'),
               priced_usage('second', 'second', 272_001, output: 1_000_000)]
    report = run_report(records, '--turn', 'first', '--turn', 'second')
    assert_metric report, 'Credits estimate', '0.005000', '1318.000250'
    assert_metric report, 'USD estimate', '$0.000200', '$80.440020'
    assert_includes report, '272K context threshold'
    assert_openai_sources report, 'gpt-5.6-terra', 'gpt-6-astra'
    refute_unrelated_cost_copy report, 'gpt-5.6-sol'
  end

  def test_unsupported_model_and_partial_counters_never_become_zero_cost
    missing = priced_usage('missing', 'current', 100)
    missing[:payload][:usage].delete(:cached_input_tokens)
    report = run_report([context('current'), missing])
    assert_metric report, 'USD estimate', 'UNKNOWN'
    refute_includes report, '0.000000'
    report = run_report([priced_context('current', 'gpt-5.6-terra'), missing])
    assert_metric report, 'Credits estimate', 'UNKNOWN'
    assert_metric report, 'USD estimate', 'UNKNOWN'
    assert_includes report, 'Incomplete billable token categories'
  end

  def test_unreported_cache_writes_and_inconsistent_subsets_keep_estimates_unknown
    setting = priced_context('current', 'gpt-5.6-terra')
    unreported = usage('first', 'current', 100)
    report = run_report([setting, unreported])
    assert_metric report, 'USD estimate', 'UNKNOWN'
    impossible = priced_usage('second', 'current', 100, cached: 90, writes: 20)
    report = run_report([setting, impossible])
    assert_includes report, 'Inconsistent token subsets'
    refute_includes report, '$0.000'
  end

  def test_anthropic_usage_has_no_unverified_price
    record = { 'configuration' => %w[anthropic UNKNOWN claude-test high],
               'usage' => { 'input_tokens' => 100, 'cached_input_tokens' => 40,
                            'cache_write_input_tokens' => 7, 'output_tokens' => 20 } }
    report = Shaka::CostEstimate.new([record]).report
    assert_metric report, 'USD estimate', 'UNKNOWN'
    refute_includes report, 'Credits estimate'
    refute_includes report, 'developers.openai.com'
    refute_includes report, 'cursor.com'
    refute_includes report, '2026-09-16'
    assert_includes report, 'Unsupported provider or configured model'
  end

  private

  def assert_openai_sources(report, *models)
    models.each { |model| assert_includes report, "models/#{model}" }
    assert_includes report, 'learn.chatgpt.com/docs/pricing'
  end

  def refute_unrelated_cost_copy(report, *models)
    models.each { |model| refute_includes report, model }
    refute_includes report, 'cursor.com'
    refute_includes report, 'Pi recorded'
  end
end

class UsageGPT6CostTest < Minitest::Test
  include UsageFixture

  RATES = {
    'gpt-6-sol' => { credits: '13.200000', base: '$0.528000', cache_write: '$0.205000',
                     long: '$16.138000' },
    'gpt-6-luna' => { credits: '0.660000', base: '$0.026400', cache_write: '$0.010250',
                      long: '$0.806900' }
  }.freeze

  def test_gpt_6_sol_published_rates
    assert_rates('gpt-6-sol')
  end

  def test_gpt_6_luna_published_rates
    assert_rates('gpt-6-luna')
  end

  private

  def assert_rates(model)
    rates = RATES.fetch(model)
    assert_standard_rates(model, rates)
    assert_cache_write_rate(model, rates)
    assert_long_context_rates(model, rates)
  end

  def assert_standard_rates(model, rates)
    records = [priced_context('standard', model),
               priced_usage('standard-response', 'standard', 200_000, cached: 40_000, output: 20_000)]
    report = run_report(records)
    assert_metric report, 'Credits estimate', rates[:credits]
    assert_metric report, 'USD estimate', rates[:base]
    assert_openai_sources report, model
  end

  def assert_cache_write_rate(model, rates)
    records = [priced_context('cache-write', model),
               priced_usage('cache-response', 'cache-write', 100_000, writes: 10_000, output: 0)]
    report = run_report(records)
    assert_metric report, 'Credits estimate', 'UNKNOWN'
    assert_metric report, 'USD estimate', rates[:cache_write]
    assert_includes report, 'Credit cache-write rate UNKNOWN'
  end

  def assert_long_context_rates(model, rates)
    records = [priced_context('long', model),
               priced_usage('long-response', 'long', 300_000,
                            cached: 20_000, writes: 10_000, output: 1_000_000)]
    report = run_report(records)
    assert_metric report, 'USD estimate', rates[:long]
    assert_includes report, '272K context threshold'
    assert_openai_sources report, model
  end

  def assert_openai_sources(report, model)
    assert_includes report, "models/#{model}"
    assert_includes report, 'learn.chatgpt.com/docs/pricing'
  end
end

class UsageCursorCostTest < Minitest::Test
  def test_cursor_grok_keeps_unpriced_writes_in_ordinary_input
    report = Shaka::CostEstimate.new([cursor_record]).report
    assert_metric report, 'Metric', 'grok-4.6'
    assert_metric report, 'USD estimate', '$0.000260'
    refute_openai_cost_copy report
    refute_includes report, 'Cursor credit rates unpublished'
    assert_includes report, 'Cursor on-demand'
    assert_includes report, 'cursor.com/docs/models/grok-4-6'
  end

  def test_cursor_grok_fast_and_missing_billing_mode
    report = Shaka::CostEstimate.new([cursor_record(billing: 'fast')]).report
    assert_metric report, 'USD estimate', '$0.000520'
    report = Shaka::CostEstimate.new([cursor_record(billing: nil)]).report
    assert_metric report, 'USD estimate', 'UNKNOWN'
    assert_includes report, 'Unsupported provider or configured model'
    refute_includes report, 'Cursor on-demand'
    refute_includes report, 'cursor.com'
    refute_includes report, '2026-09-16'
  end

  def test_cursor_named_openai_model_omits_openai_source_links
    record = { 'configuration' => %w[cursor gpt-5.6-terra cursor-terra medium],
               'billing_mode' => 'standard',
               'usage' => { 'input_tokens' => 100, 'cached_input_tokens' => 0,
                            'cache_write_input_tokens' => 0, 'output_tokens' => 20 } }
    report = Shaka::CostEstimate.new([record]).report
    assert_metric report, 'USD estimate', 'UNKNOWN'
    refute_includes report, 'developers.openai.com'
    refute_includes report, 'learn.chatgpt.com'
    refute_includes report, 'cursor.com'
    refute_includes report, 'Cursor credit rates unpublished'
  end

  def test_anthropic_named_cursor_model_omits_cursor_source_links
    record = { 'configuration' => %w[anthropic grok-4.6 claude-test high],
               'usage' => { 'input_tokens' => 100, 'cached_input_tokens' => 40,
                            'cache_write_input_tokens' => 7, 'output_tokens' => 20 } }
    report = Shaka::CostEstimate.new([record]).report
    assert_metric report, 'USD estimate', 'UNKNOWN'
    refute_includes report, 'cursor.com'
    refute_includes report, 'developers.openai.com'
  end

  def test_cursor_long_context_does_not_invent_a_threshold
    record = cursor_record(usage: { 'input_tokens' => 200_000, 'cached_input_tokens' => 0,
                                    'cache_write_input_tokens' => 0, 'output_tokens' => 0 })
    report = Shaka::CostEstimate.new([record]).report
    assert_metric report, 'USD estimate', '$0.400000'
    refute_includes report, '$0.800000'
    refute_includes report, '272K'
    refute_includes report, '256K'
  end

  def test_cursor_grok_47_prices_the_standard_card_below_256k
    report = Shaka::CostEstimate.new([cursor_record(model: 'grok-4.7')]).report
    assert_metric report, 'Metric', 'grok-4.7'
    assert_metric report, 'USD estimate', '$0.000260'
    assert_includes report, 'cursor.com/docs/models/grok-4-7'
    assert_includes report, '2026-09-21'
    refute_includes report, 'grok-4-6'
    refute_includes report, '256K'
  end

  def test_cursor_grok_47_keeps_the_base_rate_at_256k_and_prices_fast
    report = Shaka::CostEstimate.new([cursor_record(model: 'grok-4.7', usage: zero_usage(256_000))]).report
    assert_metric report, 'USD estimate', '$0.512000'
    refute_includes report, '256K'
    report = Shaka::CostEstimate.new([cursor_record(model: 'grok-4.7', billing: 'fast')]).report
    assert_metric report, 'USD estimate', '$0.000520'
  end

  def test_cursor_grok_47_long_context_scales_standard_and_fast_from_the_standard_card
    usage = zero_usage(256_001).merge('cached_input_tokens' => 1_000)
    report = Shaka::CostEstimate.new([cursor_record(model: 'grok-4.7', usage: usage)]).report
    assert_metric report, 'USD estimate', '$1.021004'
    assert_includes report, '256K context threshold'
    report = Shaka::CostEstimate.new([cursor_record(model: 'grok-4.7', billing: 'fast', usage: usage)]).report
    assert_metric report, 'USD estimate', '$1.531506'
    refute_includes report, '272K'
  end

  private

  def zero_usage(input)
    { 'input_tokens' => input, 'cached_input_tokens' => 0, 'cache_write_input_tokens' => 0, 'output_tokens' => 0 }
  end

  def cursor_record(billing: 'standard', model: 'grok-4.6', usage: {})
    { 'configuration' => ['cursor', model, "cursor-#{model}-medium", 'medium'],
      'billing_mode' => billing,
      'usage' => { 'input_tokens' => 100, 'cached_input_tokens' => 40,
                   'cache_write_input_tokens' => 7, 'output_tokens' => 20 }.merge(usage) }
  end

  def refute_openai_cost_copy(report)
    refute_includes report, 'Credits estimate'
    ['developers.openai.com', 'learn.chatgpt.com', 'Pi recorded', '0.000000'].each do |snippet|
      refute_includes report, snippet
    end
  end
end

class UsageNativePiCostTest < Minitest::Test
  def test_openai_provider_native_cost_does_not_use_rate_cards
    report = Shaka::CostEstimate.new([native_openai_record]).report
    assert_no_rate_card_copy report
    assert_metric report, 'USD estimate', '$0.000300'
    assert_includes report, 'Pi recorded native nominal USD'
  end

  def test_unavailable_native_cost_keeps_pi_provenance_not_rate_cards
    report = Shaka::CostEstimate.new([native_openai_record(cost: nil)]).report
    assert_no_rate_card_copy report
    assert_metric report, 'USD estimate', 'UNKNOWN'
    refute_includes report, 'Pi recorded native nominal USD'
  end

  def test_unsupported_openai_model_omits_rate_card_copy
    report = Shaka::CostEstimate.new([native_openai_record(cost: :omit, model: 'gpt-new')]).report
    assert_no_rate_card_copy report
    assert_metric report, 'USD estimate', 'UNKNOWN'
  end

  private

  def native_openai_record(cost: 0.0003, model: 'gpt-5.6-terra')
    usage = { 'input_tokens' => 100, 'cached_input_tokens' => 0,
              'cache_write_input_tokens' => 0, 'output_tokens' => 20 }
    usage['native_cost_usd'] = cost unless cost == :omit
    { 'configuration' => ['openai', model, 'UNKNOWN', 'high'], 'usage' => usage }
  end

  def assert_no_rate_card_copy(report)
    refute_includes report, 'Credits estimate'
    refute_includes report, '2026-09-16'
    refute_includes report, 'learn.chatgpt.com'
    refute_includes report, 'developers.openai.com'
  end
end

module AnthropicCostFixture
  ANTHROPIC_LINK = 'platform.claude.com/docs/en/about-claude/pricing'
  ANTHROPIC_FAST_LINK = 'platform.claude.com/docs/en/build-with-claude/fast-mode'

  private

  def estimate(record)
    Shaka::CostEstimate.new([record], inclusive_input: false).report
  end

  def without(record, *fields)
    fields.each { |field| record['usage'].delete(field) }
    record
  end

  def anthropic_record(configuration: %w[anthropic UNKNOWN claude-opus-5 xhigh], billing: 'standard',
                       writes: 12, writes_1h: 4, searches: 0)
    { 'configuration' => configuration, 'billing_mode' => billing,
      'usage' => { 'input_tokens' => 100, 'cached_input_tokens' => 40, 'cache_write_input_tokens' => writes,
                   'cache_write_5m_input_tokens' => writes - writes_1h,
                   'cache_write_1h_input_tokens' => writes_1h, 'output_tokens' => 20,
                   'reasoning_output_tokens' => 5, 'web_search_requests' => searches } }
  end
end

class UsageAnthropicCostTest < Minitest::Test
  include AnthropicCostFixture

  def test_standard_opus_prices_each_cache_write_at_its_own_ttl_rate
    report = estimate(anthropic_record)
    assert_metric report, 'USD estimate', '$0.001110'
    assert_includes report, 'Anthropic API list prices, verified 2026-09-23'
    assert_includes report, ANTHROPIC_LINK
    refute_includes report, ANTHROPIC_FAST_LINK
    refute_includes report, 'Credits estimate'
    refute_includes report, 'Cache-exclusive input is unpriced'
    refute_includes report, 'developers.openai.com'
    refute_includes report, 'cursor.com'
  end

  def test_one_hour_writes_cost_more_than_five_minute_writes
    hourly = estimate(anthropic_record(writes: 12, writes_1h: 12))
    five_minute = estimate(anthropic_record(writes: 12, writes_1h: 0))
    assert_metric hourly, 'USD estimate', '$0.001140'
    assert_metric five_minute, 'USD estimate', '$0.001095'
  end

  def test_the_routed_model_heads_the_column_instead_of_the_unknown_configured_model
    report = estimate(anthropic_record)
    assert_metric report, 'Metric', 'claude-opus-5'
    refute_includes report, '| Metric | UNKNOWN |'
  end

  def test_every_served_model_family_has_a_rate_including_the_cheaper_fable_cache_read
    { 'claude-opus-5-5' => '$0.000880', 'claude-opus-4-5' => '$0.001110',
      'claude-sonnet-4-5' => '$0.000666',
      'claude-haiku-4-5' => '$0.000222', 'claude-fable-5-1' => '$0.002190',
      'claude-fable-5' => '$0.002220' }.each do |model, expected|
      report = estimate(anthropic_record(configuration: ['anthropic', 'UNKNOWN', model, 'xhigh']))
      assert_metric report, 'USD estimate', expected
    end
  end

  def test_opus_55_fast_mode_doubles_its_rate_and_includes_both_sources
    configuration = %w[anthropic UNKNOWN claude-opus-5-5 xhigh]
    standard = estimate(anthropic_record(configuration: configuration))
    fast = estimate(anthropic_record(configuration: configuration, billing: 'fast'))

    assert_metric standard, 'USD estimate', '$0.000880'
    assert_includes standard, ANTHROPIC_LINK
    refute_includes standard, ANTHROPIC_FAST_LINK
    assert_metric fast, 'USD estimate', '$0.001760'
    assert_includes fast, ANTHROPIC_LINK
    assert_includes fast, ANTHROPIC_FAST_LINK
  end

  def test_web_search_requests_are_charged_on_top_of_the_token_estimate
    assert_metric estimate(anthropic_record(searches: 3)), 'USD estimate', '$0.031110'
    assert_metric estimate(anthropic_record(searches: 0)), 'USD estimate', '$0.001110'
  end

  def test_a_zero_write_total_settles_both_ttl_categories_however_few_are_named
    ['cache_write_5m_input_tokens', 'cache_write_1h_input_tokens', nil].each do |omitted|
      record = anthropic_record(writes: 0, writes_1h: 0)
      without(record, *[omitted].compact)
      assert_metric estimate(record), 'USD estimate', '$0.001020'
    end
  end

  def test_us_pinned_inference_carries_its_published_multiplier
    us = anthropic_record
    us['usage']['inference_geo'] = 'us'
    assert_metric estimate(us), 'USD estimate', '$0.001221'
    ['global', 'not_available', nil].each do |geo|
      record = anthropic_record
      record['usage']['inference_geo'] = geo
      assert_metric estimate(record), 'USD estimate', '$0.001110'
    end
  end

  def test_the_geography_multiplier_applies_to_tokens_not_to_search_requests
    us = anthropic_record(searches: 3)
    us['usage']['inference_geo'] = 'us'
    assert_metric estimate(us), 'USD estimate', '$0.031221'
  end

  def test_a_configured_model_prices_a_source_that_records_no_routed_model
    report = estimate(anthropic_record(configuration: ['anthropic', 'claude-haiku-4-5', 'UNKNOWN', 'high']))
    assert_metric report, 'USD estimate', '$0.000222'
    assert_metric report, 'Metric', 'claude-haiku-4-5'
  end

  def test_absent_cache_writes_need_no_split_to_be_priced
    none = without(anthropic_record(writes: 0, writes_1h: 0), 'cache_write_5m_input_tokens',
                   'cache_write_1h_input_tokens')
    assert_metric estimate(none), 'USD estimate', '$0.001020'
  end
end

class UsageAnthropicUnknownTest < Minitest::Test
  include AnthropicCostFixture

  def test_published_fast_mode_is_priced_and_unrecorded_speed_stays_unknown
    fast = estimate(anthropic_record(billing: 'fast'))
    assert_metric fast, 'USD estimate', '$0.002220'
    assert_includes fast, ANTHROPIC_LINK
    assert_includes fast, ANTHROPIC_FAST_LINK
    assert_includes fast, 'fast mode is priced for Opus models with a published rate'
    silent = estimate(anthropic_record(billing: 'UNKNOWN'))
    assert_metric silent, 'USD estimate', 'UNKNOWN'
    assert_includes silent, 'Billing speed UNKNOWN'
    refute_includes silent, '$0.00'
    refute_includes silent, ANTHROPIC_LINK
  end

  def test_fast_mode_for_a_model_without_a_published_rate_stays_unknown
    fast = estimate(anthropic_record(configuration: %w[anthropic UNKNOWN claude-sonnet-5 xhigh],
                                     billing: 'fast'))
    assert_metric fast, 'USD estimate', 'UNKNOWN'
    assert_includes fast, 'Anthropic fast-mode rate UNKNOWN for claude-sonnet-5'
    refute_includes fast, ANTHROPIC_LINK
    refute_includes fast, ANTHROPIC_FAST_LINK
  end

  def test_a_half_reported_cache_write_split_stays_unknown
    %w[cache_write_5m_input_tokens cache_write_1h_input_tokens].each do |field|
      report = estimate(without(anthropic_record(writes: 12), field))
      assert_metric report, 'USD estimate', 'UNKNOWN'
      assert_includes report, 'Cache-write TTL split UNKNOWN'
    end
  end

  def test_a_split_that_disagrees_with_the_published_write_total_is_not_priced
    record = anthropic_record(writes: 12, writes_1h: 4)
    record['usage']['cache_write_5m_input_tokens'] = 1
    report = estimate(record)
    assert_metric report, 'USD estimate', 'UNKNOWN'
    assert_includes report, 'Inconsistent token subsets'
    refute_includes report, '$0.00'
  end

  def test_impossible_subsets_and_unsupported_models_never_become_a_price
    over = anthropic_record(writes: 12, writes_1h: 13)
    over['usage']['cache_write_5m_input_tokens'] = 0
    over = estimate(over)
    assert_metric over, 'USD estimate', 'UNKNOWN'
    assert_includes over, 'Inconsistent token subsets'

    unsupported = estimate(anthropic_record(configuration: %w[anthropic UNKNOWN claude-test xhigh]))
    assert_metric unsupported, 'USD estimate', 'UNKNOWN'
    assert_includes unsupported, 'Unsupported provider or configured model'
    refute_includes unsupported, ANTHROPIC_LINK
    refute_includes unsupported, '2026-09-19'
  end

  def test_a_malformed_ttl_split_stays_unknown_instead_of_raising_or_discounting
    ['x', 4.0, -1].each do |split|
      record = anthropic_record(writes: 0, writes_1h: 0)
      record['usage']['cache_write_1h_input_tokens'] = split
      report = estimate(record)
      assert_metric report, 'USD estimate', 'UNKNOWN'
      assert_includes report, 'Inconsistent token subsets'
      refute_includes report, '$0.00'
    end
  end

  def test_rate_copy_describes_the_pair_so_it_survives_a_response_that_cannot_be_priced
    report = estimate(without(anthropic_record(writes: 12), 'cache_write_5m_input_tokens'))
    assert_metric report, 'USD estimate', 'UNKNOWN'
    assert_includes report, 'Anthropic API list prices'
    assert_includes report, ANTHROPIC_LINK
    assert_includes report, 'Cache-write TTL split UNKNOWN'
  end

  def test_a_search_count_the_reader_did_not_establish_stays_unknown
    ['x', -1, nil].each do |searches|
      record = anthropic_record
      record['usage']['web_search_requests'] = searches
      report = estimate(record)
      assert_metric report, 'USD estimate', 'UNKNOWN'
      assert_includes report, 'Server tool usage UNKNOWN'
    end
    assert_metric estimate(without(anthropic_record, 'web_search_requests')), 'USD estimate', 'UNKNOWN'
  end

  def test_fast_and_standard_responses_on_one_model_keep_distinguishable_columns
    records = [anthropic_record, anthropic_record(billing: 'fast')]
    report = Shaka::CostEstimate.new(records, inclusive_input: false).report
    assert_metric report, 'Metric', 'claude-opus-5', 'claude-opus-5-fast'
    refute_includes report, 'anthropic-1'
  end

  def test_a_source_whose_input_already_contains_its_subsets_is_not_priced_as_anthropic
    report = Shaka::CostEstimate.new([anthropic_record]).report
    assert_metric report, 'USD estimate', 'UNKNOWN'
    assert_includes report, 'Unsupported provider or configured model'
    refute_includes report, ANTHROPIC_LINK
    refute_includes report, '2026-09-19'
  end
end

class UsageCostLayoutTest < Minitest::Test
  include UsageFixture

  # Nested Cost scenarios hid the dollar figure behind two expansions.
  def test_usd_estimate_is_visible_without_expanding_details
    setting = priced_context('current', 'gpt-5.6-terra', effort: 'medium')
    response = priced_usage('priced', 'current', 200_000, cached: 40_000, output: 20_000)
    response[:payload][:usage][:reasoning_output_tokens] = 4_000
    report = run_report([setting, response, response])
    header = report.split('<details>').first
    assert_includes header, '| USD estimate | $0.568000 |'
    refute_includes report, '<summary>Cost scenarios</summary>'
  end
end
