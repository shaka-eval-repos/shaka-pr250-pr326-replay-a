# frozen_string_literal: true

require_relative '../error'

module Shaka
  class ReviewThread
    # Finds one review thread on this pull request and rejects a page that cannot be trusted.
    class Lookup
      MAX_PAGES = 10
      QUERY = <<~GRAPHQL
        query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100, after: $cursor) {
                nodes {
                  id
                  isResolved
                  comments(first: 100) {
                    nodes { author { login } }
                    pageInfo { hasNextPage }
                  }
                }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      GRAPHQL

      def initialize(github, thread_id)
        @github = github
        @thread_id = thread_id
      end

      def call
        cursor = nil
        MAX_PAGES.times do
          rows, info = page(cursor)
          found = rows.find { |row| row['id'] == @thread_id }
          return found if found
          return missing unless info['hasNextPage']

          cursor = advance(cursor, info)
        end
        raise Error, "Review-thread list exceeds #{MAX_PAGES} pages."
      end

      private

      def page(cursor)
        owner, name = @github.repository.split('/')
        connection = threads(@github.graphql(QUERY, owner:, name:, number: @github.number, cursor:))
        raise Error, 'Review-thread evidence is unavailable.' unless connection.is_a?(Hash)

        rows, info = connection.values_at('nodes', 'pageInfo')
        raise Error, 'Review-thread response is malformed.' unless rows.is_a?(Array) && page?(info)

        rows.each { |row| check_row(row) }
        [rows, info]
      end

      def threads(data)
        repository = data['repository']
        pull = repository['pullRequest'] if repository.is_a?(Hash)
        pull['reviewThreads'] if pull.is_a?(Hash)
      end

      def check_row(row)
        raise Error, 'Review-thread response is malformed.' unless valid_row?(row)
      end

      def valid_row?(row)
        return false unless row.is_a?(Hash) && row['id'].is_a?(String) && boolean?(row['isResolved'])

        valid_comments?(row['comments'])
      end

      def valid_comments?(comments)
        return false unless comments.is_a?(Hash)

        nodes, info = comments.values_at('nodes', 'pageInfo')
        nodes.is_a?(Array) && page?(info)
      end

      def page?(info)
        info.is_a?(Hash) && boolean?(info['hasNextPage'])
      end

      def boolean?(value)
        [true, false].include?(value)
      end

      def advance(cursor, info)
        nxt = info['endCursor']
        return nxt if nxt.is_a?(String) && !nxt.empty? && nxt != cursor

        raise Error, 'Review-thread pagination did not advance.'
      end

      def missing
        raise Error, 'The review thread is not on this pull request.'
      end
    end
  end
end
