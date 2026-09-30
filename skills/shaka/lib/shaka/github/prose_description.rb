# frozen_string_literal: true

# Applies the prose limits to a description before Publishing merges and writes it.

require_relative '../prose_limits'

module Shaka
  # Measures only Shaka's text, before Publishing merges it with what others wrote.
  module ProseDescription
    def description(body: nil, prose: ProseLimits.new)
      super() do |current|
        text = check_length(publishable(block_given? ? yield(current) : body))
        prose.verify_publication!(self, text, kind: :description, pull: current)
        text
      end
    end
  end
end
