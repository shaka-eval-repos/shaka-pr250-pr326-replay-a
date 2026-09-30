# frozen_string_literal: true

require_relative '../error'

module Shaka
  module PublicComments
    # Joins GitHub's native review-thread state to REST inline comments by ID.
    class Threads
      MAX_THREAD_PAGES = 10
      QUERY = <<~GRAPHQL
        query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100, after: $cursor) {
                nodes {
                  id isResolved
                  comments(first: 100) {
                    nodes { fullDatabaseId }
                    pageInfo { hasNextPage }
                  }
                }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      GRAPHQL

      def initialize(github)
        @github = github
      end

      def call
        cursor = nil
        threads = []
        index = {}
        (1..MAX_THREAD_PAGES).each do
          rows, page = fetch_page(cursor)
          rows.each { |row| add_thread(row, threads, index) }
          return [threads, index] unless page['hasNextPage']

          cursor = advance_cursor(cursor, page)
        end
        raise Error, "Review-thread list exceeds #{MAX_THREAD_PAGES} pages."
      end

      private

      def fetch_page(cursor)
        owner, name = @github.repository.split('/')
        response = @github.graphql(QUERY, owner: owner, name: name, number: @github.number, cursor: cursor)
        connection = thread_connection(response)
        raise Error, 'Review-thread evidence is unavailable.' unless connection.is_a?(Hash)

        rows, page = connection.values_at('nodes', 'pageInfo')
        raise Error, 'Review-thread response is malformed.' unless rows.is_a?(Array) && valid_page?(page)

        [rows, page]
      end

      def thread_connection(response)
        repository = response['repository']
        pull = repository['pullRequest'] if repository.is_a?(Hash)
        pull['reviewThreads'] if pull.is_a?(Hash)
      end

      def valid_page?(page)
        page.is_a?(Hash) && boolean?(page['hasNextPage'])
      end

      def boolean?(value)
        [true, false].include?(value)
      end

      def advance_cursor(cursor, page)
        next_cursor = page['endCursor']
        if !next_cursor.is_a?(String) || next_cursor.empty? || next_cursor == cursor
          raise Error, 'Review-thread pagination did not advance.'
        end

        next_cursor
      end

      def add_thread(row, threads, index)
        meta, comments = normalize_thread(row)
        threads << meta
        comments.each { |comment| index_comment(comment, meta, index) }
      end

      def normalize_thread(row)
        connection = row['comments'] if row.is_a?(Hash)
        comments, page = connection.values_at('nodes', 'pageInfo') if connection.is_a?(Hash)
        raise Error, 'Review-thread response is malformed.' unless valid_thread?(row, comments, page)

        # REST replies refer to the first comment, so truncated reply pages still join.
        raise Error, 'Review thread has no root comment.' if comments.empty?

        [{ 'thread_id' => row['id'], 'is_resolved' => row['isResolved'] }, comments]
      end

      def valid_thread?(row, comments, page)
        row.is_a?(Hash) && row['id'].is_a?(String) && boolean?(row['isResolved']) &&
          comments.is_a?(Array) && valid_page?(page)
      end

      def index_comment(comment, meta, index)
        raw = comment['fullDatabaseId'] if comment.is_a?(Hash)
        raise Error, 'Review-thread comment ID is unavailable.' unless raw.is_a?(String) && raw.match?(/\A[1-9]\d*\z/)

        id = Integer(raw, 10)
        raise Error, 'Review comment belongs to multiple threads.' if index.key?(id) && index[id] != meta

        index[id] = meta
      end
    end
  end
end
