# frozen_string_literal: true

require_relative '../public_comments/bounded_list'
require_relative '../walkthrough/history'

module Shaka
  class Handoff
    # Finds the commit the current walkthrough explains, counting only evidence this account controls.
    class Walkthrough
      def initialize(github)
        @github = github
      end

      # Superseded walkthroughs are wrapped in a pointer, so only the current one still renders as a
      # walkthrough. Only this account's reviews count, so a commenter's copy cannot change what is owed.
      def revision
        account = @github.api('user')['login']
        current = reviews.reverse.find do |review|
          review.dig('user', 'login') == account && review['state'] == 'COMMENTED' &&
            WalkthroughText.rendered?(review['body'].to_s)
        end
        current && bound_revision(current)
      end

      private

      def reviews
        path = "repos/#{@github.repository}/pulls/#{@github.number}/reviews"
        PublicComments::BoundedList.new(@github, max_pages: 5, label: 'Review listing').call(path)
      end

      # GitHub binds a review to its commit; the footer is editable text, so it only counts when it agrees.
      def bound_revision(review)
        commit = review['commit_id']
        commit if commit.is_a?(String) && WalkthroughText.revision(review['body']) == commit
      end
    end
  end
end
