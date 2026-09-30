# frozen_string_literal: true

module Shaka
  # Structural checks a carried or new report must pass before it can keep or replace history.
  module UsageRecordShape
    module_function

    # A carried block must still look like the helper's report, so an edit cannot hide more
    # markers or unbalanced markup under the managed output.
    def report_shape?(text)
      inner = text.sub(/\A.*?\n/, '').delete_suffix(UsageRecords::END_MARK)
      !inner.include?('<!-- shaka:') && balanced_details?(inner)
    end

    # Only the helper's own lowercase tags are accepted; any other form could close the outer disclosure.
    def balanced_details?(text)
      tags = text.scan(%r{</?details\b[^>]*>}i)
      return false unless tags.all? { |tag| ['<details>', '</details>'].include?(tag) }

      depth = tags.reduce(0) do |open, tag|
        return false if tag == '</details>' && open.zero?

        tag == '</details>' ? open - 1 : open + 1
      end
      depth.zero?
    end
  end
end
