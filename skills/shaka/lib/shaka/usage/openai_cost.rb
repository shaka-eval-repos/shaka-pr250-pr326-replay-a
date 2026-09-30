# frozen_string_literal: true

module Shaka
  # OpenAI API-equivalent and Codex credit rates, including the API context threshold.
  module OpenAICost
    private

    def openai_price(model, mode, tokens)
      rate = @rate_card.openai_rate(model, mode)
      return [nil, 'Unsupported provider or configured model'] unless rate
      return [nil, 'Credit cache-write rate UNKNOWN'] if mode == :credits && tokens[2].positive?

      [bill(tokens, rate, mode) / 1_000_000, nil]
    end

    def bill(tokens, rate, mode)
      large = mode == :api && tokens[0] > @rate_card.openai_threshold
      @threshold = true if large
      (input_bill(tokens, rate, mode) * (large ? 2 : 1)) +
        (tokens[3] * Rational(rate[2]) * (large ? Rational(3, 2) : 1))
    end

    def input_bill(tokens, rate, mode)
      input, cached, writes = tokens
      input_rate, cached_rate = rate.first(2).map { |value| Rational(value) }
      amount = ((input - cached - writes) * input_rate) + (cached * cached_rate)
      mode == :api ? amount + (writes * input_rate * Rational(5, 4)) : amount
    end
  end
end
