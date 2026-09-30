# frozen_string_literal: true

require_relative '../error'
require_relative '../public_comments/bounded_list'

module Shaka
  # Posts the squash commit message a maintainer pastes into GitHub's squash merge boxes.
  # Each head gets a new comment at the bottom of the timeline, beside the merge button, and
  # the older ones this account posted are deleted once the new one is confirmed.
  module SquashComment
    SQUASH_MARK = '<!-- shaka:squash-message -->'
    COMMENT_PAGES = 20
    HEAD = /\A#{Regexp.escape(SQUASH_MARK)}\n<!-- head (\h{40}) -->\n/

    # The full head a posted comment names, or nil when its opening lines are not the ones
    # `squash_comment` writes. The displayed short SHA is not enough: a fork can mint a head sharing it.
    def self.head(body) = body.to_s.gsub("\r\n", "\n")[HEAD, 1]

    def squash_comment(head:, message:)
      verify_head(head)
      body = squash_comment_body(head, message)
      posted = api("repos/#{@repository}/issues/#{@number}/comments", method: 'POST', fields: { body: body })
      confirmed(posted, body)
      { 'url' => posted['html_url'], 'id' => posted['id'], 'headline' => message.headline,
        'deleted' => delete_earlier_squash_comments(posted['id']) }
    end

    private

    # The fence outruns any backtick run in the message, so the text cannot close its block.
    def squash_comment_body(head, message)
      fence = '`' * [3, "#{message.headline}\n#{message.body}".scan(/`+/).map(&:length).max.to_i + 1].max
      <<~MARKDOWN
        #{SQUASH_MARK}
        <!-- head #{head} -->
        **Squash commit message for `#{head[0, 7]}`.** Paste the title and the body into GitHub's squash merge boxes.

        #{fence}text
        #{message.headline}
        #{fence}

        #{fence}text
        #{message.body}
        #{fence}
      MARKDOWN
    end

    def delete_earlier_squash_comments(kept)
      earlier_squash_comments(kept).map do |comment|
        id = positive_integer(comment['id'])
        capture(['gh', 'api', "repos/#{@repository}/issues/comments/#{id}", '--method', 'DELETE'])
        id
      end
    end

    # Only an older comment this account wrote, whose body opens with the marker, is ours to
    # delete. Comment IDs increase, so a concurrent run's newer comment survives this one.
    def earlier_squash_comments(kept)
      account = viewer
      PublicComments::BoundedList.new(self, max_pages: COMMENT_PAGES, label: 'Comment listing')
                                 .call("repos/#{@repository}/issues/#{@number}/comments")
                                 .select do |comment|
        comment['id'].is_a?(Integer) && comment['id'] < kept && comment['body'].to_s.start_with?(SQUASH_MARK) &&
          comment.dig('user', 'login') == account
      end
    end
  end
end
