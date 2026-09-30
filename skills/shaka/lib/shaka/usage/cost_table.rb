# frozen_string_literal: true

module Shaka
  # Metric-row cost table and source links for the models actually priced.
  module CostTable
    MODEL_SOURCES = {
      'gpt-5.6-terra' => '[Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra)',
      'gpt-5.6-sol' => '[GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)',
      'gpt-6-astra' => '[Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)',
      'gpt-6-sol' => '[GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)',
      'gpt-6-luna' => '[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)',
      'grok-4.6' => '[Cursor Grok 4.6](https://cursor.com/docs/models/grok-4-6)',
      'grok-4.7' => '[Cursor Grok 4.7](https://cursor.com/docs/models/grok-4-7)'
    }.freeze
    CREDIT_SOURCE = '[Codex credit rates](https://learn.chatgpt.com/docs/pricing#token-rates)'
    CACHE_SOURCE = '[prompt-cache accounting](https://developers.openai.com/api/docs/guides/prompt-caching)'
    CURSOR_PRICING = '[Cursor model pricing](https://cursor.com/docs/models-and-pricing)'
    ANTHROPIC_PRICING = '[Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing)'
    ANTHROPIC_FAST_PRICING = '[Anthropic fast-mode pricing]' \
                             '(https://platform.claude.com/docs/en/build-with-claude/fast-mode)'

    private

    def cost_table(columns)
      headers = cost_headers(columns)
      [line(['Metric', *headers]), line(['---'] * (headers.size + 1)), *estimate_rows(columns)].join("\n")
    end

    def estimate_rows(columns)
      rows = []
      if credits_row?(columns)
        rows << line(['Credits estimate', *columns.map { |column| shown(column, :credits, 'credits') }])
      end
      rows << line(['USD estimate', *columns.map { |column| shown(column, :api, '$') }])
    end

    def shown(column, key, unit)
      amount = show(column[key], unit)
      column[:"#{key}_partial"] ? "#{amount} (partial)" : amount
    end

    def cost_headers(columns)
      labeled = columns.map { |column| setting_cells(column) }
      candidates = header_candidates(labeled)
      distinct(candidates.reject { |names| names.include?('UNKNOWN') }) || distinct(candidates) ||
        labeled.map.with_index { |cells, index| "#{cells[0]}-#{index + 1}" }
    end

    def distinct(candidates)
      candidates.find { |names| names.uniq.size == names.size }
    end

    def setting_cells(column)
      [column[:provider], column[:model], column[:routed], column[:effort]].map { |value| safe(value) }
    end

    def header_candidates(labeled)
      [1, 2, 3, 0].map { |index| labeled.map { |cells| cells[index] } } +
        [[1, 3], [0, 1, 3], [0, 1, 2, 3]].map do |indexes|
          labeled.map { |cells| indexes.map { |index| cells[index] }.join(' ') }
        end
    end

    def credits_row?(columns)
      priced_columns(columns).any? { |column| openai_rated?(column) || column[:credits] }
    end

    def source_line(columns)
      links = source_links(columns)
      return if links.empty?

      "Sources: #{join_english(links)}."
    end

    def source_links(columns)
      priced = priced_columns(columns)
      fast_anthropic = priced.any? { |column| column[:billing] == 'fast' && anthropic_rated?(column) }
      [*rate_card_links(priced), (CURSOR_PRICING if cursor_priced?(priced)),
       (ANTHROPIC_PRICING if anthropic_priced?(priced)),
       (ANTHROPIC_FAST_PRICING if fast_anthropic)].compact
    end

    def rate_card_links(priced)
      return model_source_links(priced) unless openai_priced?(priced)

      [CREDIT_SOURCE, *model_source_links(priced), CACHE_SOURCE]
    end

    def model_source_links(columns)
      columns.filter_map do |column|
        next unless openai_rated?(column) || cursor_rated?(column)

        MODEL_SOURCES[column[:model].to_s.delete_suffix('-fast')]
      end.uniq
    end

    def join_english(items)
      return items.first if items.size == 1
      return items.join(' and ') if items.size == 2

      "#{items[0..-2].join(', ')}, and #{items.last}"
    end

    def line(cells) = "| #{cells.join(' | ')} |"
  end
end
