# frozen_string_literal: true

module Shaka
  # Report copy for the rate-card cost scenarios.
  module CostCopy
    private

    def markdown(columns, reasons)
      parts = [cost_table(columns),
               "Rate card: #{@rate_card.label}.",
               intro(columns),
               footer(columns, reasons)].compact.reject { |part| part.to_s.strip.empty? }
      "#{parts.join("\n\n")}\n"
    end

    def intro(columns)
      [rate_intro(columns), (native_intro if columns.any? { |column| column[:native] })].compact.join(' ')
    end

    def rate_intro(columns)
      sentences = [rate_card_intro(columns), anthropic_intro(columns)].compact
      sentences.join(' ') unless sentences.empty?
    end

    def rate_card_intro(columns)
      sentences = rate_card_sentences(priced_columns(columns))
      "#{sentences.join('. ')}." unless sentences.empty?
    end

    def rate_card_sentences(priced)
      [
        (openai_sentence if openai_priced?(priced)),
        (cursor_sentence if cursor_priced?(priced))
      ].compact
    end

    def openai_sentence
      "Standard Codex credit and OpenAI API-equivalent rates, verified #{@rate_card.openai_verified}"
    end

    def cursor_sentence
      "Cursor on-demand list prices, verified #{@rate_card.cursor_verified}"
    end

    def anthropic_intro(columns)
      return unless anthropic_priced?(priced_columns(columns))

      "Anthropic API list prices, verified #{@rate_card.anthropic_verified}. Uncached input, cache reads and " \
        'cache writes are separate charges, and a 1-hour cache write costs more than a 5-minute one. ' \
        'Standard-speed responses are priced; fast mode is priced for Opus models with a published rate.'
    end

    def openai_priced?(priced) = priced.any? { |column| openai_rated?(column) }
    def cursor_priced?(priced) = priced.any? { |column| cursor_rated?(column) }
    def anthropic_priced?(priced) = priced.any? { |column| anthropic_rated?(column) }

    def native_intro
      'Pi recorded native nominal USD.'
    end

    def priced_columns(columns)
      columns.reject { |column| column[:recorded_native] }
    end

    def openai_rated?(column)
      column[:provider] == 'openai' && @rate_card.openai_model?(column[:model])
    end

    def cursor_rated?(column)
      model = column[:model].to_s.delete_suffix('-fast')
      column[:provider] == 'cursor' && @rate_card.cursor_model?(model, column[:billing])
    end

    # Rate-card copy describes the provider and model pair's rate card, as it does for every
    # other provider, so it stays beside an UNKNOWN a response's own counters caused.
    def anthropic_rated?(column)
      return false unless column[:provider] == 'anthropic' && !@inclusive_input

      model = @rate_card.anthropic_name(column[:routed], column[:model], column[:billing])
      @rate_card.anthropic_speed?(model, column[:billing])
    end

    def footer(columns, reasons)
      [reasons.uniq.join('; '), source_line(columns), (@threshold ? openai_threshold_note : nil),
       cursor_threshold_note].compact.reject(&:empty?).join("\n")
    end

    def openai_threshold_note
      "OpenAI API estimates apply the #{threshold_label(@rate_card.openai_threshold)} context threshold."
    end

    def cursor_threshold_note
      return if @cursor_threshold_models.nil? || @cursor_threshold_models.empty?

      @cursor_threshold_models.uniq.map do |model, limit|
        "Cursor #{model} estimates apply the #{threshold_label(limit)} context threshold."
      end.join("\n")
    end

    def threshold_label(value)
      value.is_a?(Integer) && (value % 1_000).zero? ? "#{value / 1_000}K" : value.to_s
    end

    def show(amount, unit)
      return 'UNKNOWN' unless amount

      formatted = format('%.6f', amount)
      unit == '$' ? "$#{formatted}" : formatted
    end

    def safe(value)
      value.is_a?(String) && value.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,79}\z/) ? value : 'UNKNOWN'
    end
  end
end
