# frozen_string_literal: true

module Shaka
  # Anthropic list prices, which bill uncached input, cache reads and cache writes separately.
  module AnthropicCost
    # Fast mode is 2x standard rates. Cache multipliers stack on top, so the same
    # multiplier applies to every token category. The rate card names which models publish it.

    # Web search bills $10 per 1,000 requests on top of tokens; web fetch adds no charge.
    # Readers report no searches as zero, so a count that is absent here was never established.
    SEARCH_RATE = Rational(1, 100)
    # Pinning inference to the US multiplies every token category. Global is the default, so a
    # record that does not name US routing is priced at standard rates rather than refused.
    US_GEO_RATE = Rational(11, 10)

    private

    # Claude Code records only the routed model; exports that name a configured model use that.
    def anthropic_price(record, mode)
      return [nil, 'Codex credits do not price Anthropic'] if mode == :credits

      rate, reason = anthropic_rate_for(record['configuration'], record['billing_mode'])
      return [nil, reason] if reason

      priced, reason = anthropic_categories(record['usage'])
      reason ? [nil, reason] : [anthropic_bill(priced, rate), nil]
    end

    def anthropic_rate_for(configuration, speed)
      return [nil, 'Unsupported provider or configured model'] unless configuration.is_a?(Array)

      _provider, configured, routed = configuration
      model = @rate_card.anthropic_name(routed, configured, speed)
      return [nil, 'Unsupported provider or configured model'] unless model

      return [nil, speed_reason(speed, model)] unless @rate_card.anthropic_speed?(model, speed)

      rates = @rate_card.anthropic_prices(model).map { |price| Rational(price) }
      rates = rates.map { |price| price * 2 } if speed == 'fast'
      [rates, nil]
    end

    # Claude model rates apply only where the provider publishes the corresponding speed.
    def speed_reason(speed, model)
      speed == 'fast' ? "Anthropic fast-mode rate UNKNOWN for #{model}" : 'Billing speed UNKNOWN'
    end

    def anthropic_bill(priced, rate)
      tokens, searches, geo = priced
      billed = tokens.zip(rate).sum { |count, price| count * Rational(price) } / 1_000_000
      (billed * (geo == 'us' ? US_GEO_RATE : 1)) + (searches * SEARCH_RATE)
    end

    def anthropic_categories(usage)
      return [nil, 'Incomplete billable token categories'] unless usage.is_a?(Hash)

      counters = %w[input_tokens cached_input_tokens cache_write_input_tokens output_tokens].map { |key| usage[key] }
      return [nil, 'Incomplete billable token categories'] unless valid_counters?(counters)

      input, cached, writes, output = counters
      split = write_split(usage, writes)
      searches = usage['web_search_requests']
      reason = anthropic_reason(usage, writes, split, [searches, output])
      reason ? [nil, reason] : [[[input, cached, *split, output], searches, usage['inference_geo']], nil]
    end

    def anthropic_reason(usage, writes, split, tools)
      searches, output = tools
      anthropic_subset_reason(writes, split, usage['reasoning_output_tokens'], output) ||
        ('Server tool usage UNKNOWN' unless valid_counters?([searches]))
    end

    # A zero write total already establishes both TTL categories, however few the transcript names.
    def write_split(usage, writes)
      split = %w[cache_write_5m_input_tokens cache_write_1h_input_tokens].map { |key| usage[key] }
      writes.zero? ? split.map { |count| count || 0 } : split
    end

    # The two cache-write rates differ, so only a split that accounts for the whole total is priced.
    def anthropic_subset_reason(writes, split, reasoning, output)
      return 'Cache-write TTL split UNKNOWN' if split.any?(&:nil?)
      return 'Inconsistent token subsets' unless valid_counters?(split) && split.sum == writes

      'Inconsistent token subsets' if invalid_reasoning?(reasoning, output)
    end
  end
end
