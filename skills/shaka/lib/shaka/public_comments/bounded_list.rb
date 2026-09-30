# frozen_string_literal: true

require_relative '../error'

module Shaka
  module PublicComments
    # Fetches REST list pages with an explicit request and item limit.
    class BoundedList
      PAGE_SIZE = 100
      class LimitError < Error; end

      def initialize(github, max_pages:, label:)
        @github = github
        @max_pages = max_pages
        @label = label
      end

      def call(path)
        rows = []
        (1..(@max_pages + 1)).each do |page|
          batch = fetch_page(path, page)
          rows.concat(batch)
          break if batch.length < PAGE_SIZE
        end
        rows
      end

      private

      def fetch_page(path, page)
        rows = @github.api_list("#{path}?per_page=#{PAGE_SIZE}&page=#{page}")
        raise Error, "#{@label} response is malformed." unless rows.length <= PAGE_SIZE && rows.all?(Hash)
        raise LimitError, "#{@label} exceeds #{@max_pages} pages." if page > @max_pages && !rows.empty?

        rows
      end
    end
  end
end
