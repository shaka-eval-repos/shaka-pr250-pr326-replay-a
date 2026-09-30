# frozen_string_literal: true

require_relative '../github/squash_comment'
require_relative '../public_comments/bounded_list'

module Shaka
  class Handoff
    # Finds the head the current squash commit message names, counting only this account's comments.
    class SquashNote
      def initialize(github)
        @github = github
      end

      # `squash-message` deletes older copies, but the newest comment still wins if a deletion failed.
      def head
        account = @github.api('user')['login']
        ours = comments.select { |comment| comment.dig('user', 'login') == account && comment['id'].is_a?(Integer) }
        latest = ours.filter_map { |comment| (head = SquashComment.head(comment['body'])) && [comment['id'], head] }
        latest.max_by(&:first)&.last
      end

      private

      def comments
        path = "repos/#{@github.repository}/issues/#{@github.number}/comments"
        PublicComments::BoundedList.new(@github, max_pages: SquashComment::COMMENT_PAGES, label: 'Comment listing')
                                   .call(path)
      end
    end
  end
end
