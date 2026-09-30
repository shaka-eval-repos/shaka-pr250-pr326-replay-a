# frozen_string_literal: true

module Shaka
  class Doctor
    # One answered question, in the shape the report renders.
    module Check
      def check(name, status, summary, guidance: nil)
        { name: name, status: status, summary: summary, guidance: guidance }
      end

      def first_line(text) = text.to_s.lines.first.to_s.strip
    end
  end
end
