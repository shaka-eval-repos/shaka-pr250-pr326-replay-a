# frozen_string_literal: true

require_relative 'rate_card'
require_relative 'cursor_cost'
require_relative 'anthropic_cost'
require_relative 'openai_cost'
require_relative 'cost_copy'
require_relative 'cost_table'
require_relative 'cost_columns'

module Shaka
  # Prices rate-card scenarios from disjoint per-response token categories, on the configured
  # model where a source records one and on the routed model where it does not.
  class CostEstimate
    include CursorCost
    include AnthropicCost
    include OpenAICost
    include CostCopy
    include CostTable
    include CostColumns

    def initialize(responses, inclusive_input: true, rate_card: nil)
      @responses = responses
      @inclusive_input = inclusive_input
      @rate_card = rate_card || RateCard.installed
      @cursor_threshold_models = []
    end

    def report
      data = snapshot
      markdown(data[:columns], data[:reasons])
    end

    # One pass of the priced columns, in the same order `report` prints them.
    def snapshot
      @threshold = false
      @cursor_threshold_models = []
      reasons = []
      groups = @responses.group_by { |record| [record['configuration'], record['billing_mode']] }
      columns = groups.map { |key, group| column(key, group, reasons) }
      columns = [blank_column] if columns.empty?
      { columns: columns, reasons: reasons, groups: groups.values }
    end

    def column_headers(columns) = cost_headers(columns)

    def display(column, key, unit) = shown(column, key, unit)

    def narrative_for(data)
      ["Rate card: #{@rate_card.label}.", intro(data[:columns]),
       footer(data[:columns], data[:reasons])].compact.reject { |part| part.to_s.strip.empty? }.join("\n\n")
    end

    private

    # Responses that can be priced keep their estimate, marked partial, beside the ones that cannot.
    def total(group, mode)
      priced, unpriced = group.map { |record| price(record, mode) }.partition { |_, reason| reason.nil? }
      return [nil, unpriced.first.last, false] if priced.empty? && unpriced.any?

      sum = priced.sum { |amount, _| amount }
      unpriced.empty? ? [sum, nil, false] : [sum, partial_reason(unpriced, group.size), true]
    end

    def partial_reason(unpriced, count)
      "Partial estimate: #{unpriced.size} of #{count} responses unpriced (#{unpriced.map(&:last).uniq.join('; ')})."
    end

    # The OpenAI and Cursor rates bill input inclusive of its cached and written subsets;
    # the Anthropic rates bill those three separately and are priced on their own path.
    def price(record, mode)
      native_price(record, mode) || configured_price(record, mode)
    end

    def native_price(record, mode)
      usage = record['usage']
      return unless usage.is_a?(Hash) && usage.key?('native_cost_usd')
      return [nil, 'Codex credit estimate unavailable for Pi'] if mode == :credits

      value = usage['native_cost_usd']
      return [nil, 'Native nominal cost unavailable'] unless value.is_a?(Numeric) && value.finite? && value >= 0

      [value, nil]
    end

    def configured_price(record, mode)
      provider, model = record['configuration']
      return anthropic_price(record, mode) if provider == 'anthropic' && !@inclusive_input
      return [nil, 'Cache-exclusive input is unpriced'] unless @inclusive_input
      return [nil, 'Unsupported provider or configured model'] unless %w[openai cursor].include?(provider)

      tokens, reason = categories(record['usage'])
      return [nil, reason] if reason

      return openai_price(model, mode, tokens) if provider == 'openai'

      cursor_price(model, record['billing_mode'], mode, tokens)
    end

    def categories(usage)
      return [nil, 'Incomplete billable token categories'] unless usage.is_a?(Hash)

      tokens = %w[input_tokens cached_input_tokens cache_write_input_tokens output_tokens].map { |field| usage[field] }
      return [nil, 'Incomplete billable token categories'] unless valid_counters?(tokens)

      input, cached, writes, output = tokens
      reasoning = usage['reasoning_output_tokens']
      return [nil, 'Inconsistent token subsets'] if cached + writes > input || invalid_reasoning?(reasoning, output)

      [tokens, nil]
    end

    def valid_counters?(tokens)
      tokens.all? { |value| value.is_a?(Integer) && value >= 0 }
    end

    def invalid_reasoning?(reasoning, output)
      reasoning.is_a?(Integer) && (reasoning.negative? || reasoning > output)
    end
  end
end
