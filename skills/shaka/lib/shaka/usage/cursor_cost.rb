# frozen_string_literal: true

module Shaka
  # Cursor on-demand list prices; credits stay unpublished.
  module CursorCost
    private

    def cursor_price(model, billing, mode, tokens)
      return [nil, 'Cursor credit rates unpublished'] if mode == :credits

      rate = cursor_rates(model, billing, tokens[0])
      return [nil, 'Unsupported provider or configured model'] unless rate

      input, cached, _, output = tokens
      [(((input - cached) * rate[0]) + (cached * rate[1]) + (output * rate[2])) / 1_000_000, nil]
    end

    # Input above the model's threshold uses a multiple of its standard rates.
    def cursor_rates(model, billing, input)
      listed = @rate_card.cursor_rate(model, billing)
      return unless listed

      limit = @rate_card.cursor_threshold(model)
      return listed.map { |value| Rational(value) } unless limit && input > limit

      @cursor_threshold_models << [model.to_s, limit]
      multiple = @rate_card.cursor_long_context(billing)
      @rate_card.cursor_rate(model, 'standard').map { |value| Rational(value) * multiple }
    end
  end
end
