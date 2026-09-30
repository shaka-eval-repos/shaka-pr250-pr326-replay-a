# frozen_string_literal: true

module Shaka
  class GitHub
    # The reads merge uses to find a posted local review and compare later commits with it.
    module ReviewEvidenceReads
      COMPARE_START = %r{\A(?!.*\.\.)[A-Za-z0-9_][A-Za-z0-9._/-]*\z}
      COMMIT = /\A[0-9a-f]{40}\z/

      def viewer_login = viewer

      def issue_comments
        PublicComments::BoundedList.new(self, max_pages: Publishing::REPLY_PAGES, label: 'Comment listing')
                                   .call("repos/#{@repository}/issues/#{@number}/comments")
      end

      # `from` may be the PR's base branch; `to` is always a commit.
      def compare(from, to)
        raise Error, 'Expected a full commit SHA.' unless to.to_s.match?(COMMIT)
        raise Error, 'Expected a commit SHA or branch name.' unless from.to_s.match?(COMPARE_START)

        api("repos/#{@repository}/compare/#{from}...#{to}")
      end
    end
  end
end
