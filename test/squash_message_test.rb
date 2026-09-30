# frozen_string_literal: true

require_relative 'github_helper'
require_relative 'merge_test'
require 'shaka/publication/squash_message'

class SquashMessageTest < Minitest::Test
  def squash(body: 'Summary.', title: 'Write better squash commits', messages: [])
    Shaka::SquashMessage.new({ 'title' => title, 'body' => body }, number: 42, commit_messages: messages)
  end

  def test_the_headline_ends_with_the_pr_number_once
    assert_equal 'Write better squash commits (#42)', squash.headline
    assert_equal 'Already numbered (#42)', squash(title: 'Already numbered (#42)').headline
  end

  def test_the_body_wraps_paragraphs_and_list_items_for_git_log
    words = Array.new(30) { |index| "word#{index}" }.join(' ')
    paragraph, list = wrapped(squash(body: "#{words}\n\n- #{words}\n- short").body).split("\n\n")

    assert_equal words, paragraph.split.join(' ')
    assert_match(/\A- word0 .*\n  word/m, list)
    assert_equal '- short', list.lines.last
  end

  def wrapped(body)
    assert(body.lines.all? { |line| line.chomp.length <= 72 }, body)
    body
  end

  def test_a_word_longer_than_the_width_stays_whole
    url = "https://example.test/#{'x' * 90}"

    assert_equal "See\n#{url}\nfor details.", squash(body: "See #{url} for details.").body
  end

  def test_co_author_trailers_from_the_branch_commits_are_carried_once
    claude = 'Claude Opus 5.5 <noreply@anthropic.com>'
    messages = ["Fix\n\nCo-Authored-By: #{claude}",
                "Tidy\n\nco-authored-by: #{claude.downcase}\nCo-authored-by: Ana <ana@example.test>", 'No trailer']

    assert_equal "Summary.\n\nCo-authored-by: Claude Opus 5.5 <noreply@anthropic.com>\n" \
                 'Co-authored-by: Ana <ana@example.test>', squash(messages:).body
  end

  def test_a_trailer_example_inside_the_body_is_not_a_co_author
    messages = ["Document attribution\n\nCo-authored-by: Example <example@example.test>\n\nThis is sample syntax."]

    assert_equal 'Summary.', squash(messages:).body
  end

  def test_markdown_meant_for_a_pr_description_is_refused
    ["```ruby\nx\n```", "<details>\n<summary>Usage</summary>", "| a | b |\n| --- | --- |"].each do |body|
      error = assert_raises(Shaka::Error) { squash(body:) }
      assert_match(/plain text for git log/, error.message)
    end
  end

  def test_a_multiline_or_missing_title_is_refused
    assert_raises(Shaka::Error) { squash(title: "One\nTwo") }
    assert_raises(Shaka::Error) { squash(title: ' ') }
  end
end

class SquashMessageCommitsTest < Minitest::Test
  Listing = Struct.new(:repository, :number, :commits, :total) do
    def api_list(_path) = commits
    def snapshot = { 'commits' => { 'totalCount' => total } }
  end

  def build(commits, total)
    Shaka::SquashMessage.for(Listing.new('owner/repo', 42, commits, total), { 'title' => 'T', 'body' => 'B' })
  end

  def test_trailers_come_from_every_listed_commit
    commits = [{ 'commit' => { 'message' => "Fix\n\nCo-authored-by: Ana <ana@example.test>" } }]

    assert_equal "B\n\nCo-authored-by: Ana <ana@example.test>", build(commits, 1).body
  end

  def test_a_pr_with_more_commits_than_github_lists_is_refused
    error = assert_raises(Shaka::Error) { build([{ 'commit' => { 'message' => 'Fix' } }], 300) }
    assert_match(/only some of the PR commits/, error.message)
  end
end

class SquashCommentTest < Minitest::Test
  include GitHubHelper

  MARK = Shaka::SquashComment::SQUASH_MARK

  def squash_message = Shaka::SquashMessage.new({ 'title' => 'T', 'body' => 'B' }, number: 42)

  def listed(id, login, body = "#{MARK}\nold") = { 'id' => id, 'user' => { 'login' => login }, 'body' => body }

  # GitHub echoes the stored body, so the POST answer repeats what was submitted.
  def stored(body) = response({ 'id' => 10, 'html_url' => 'https://example.test/c/10', 'body' => body })

  def expected_body = Shaka::GitHub.new('owner/repo', 42).send(:squash_comment_body, HEAD, squash_message)

  # Only 7 is ours to delete: 8 is someone else's, 9 lacks the marker, 10 is the new
  # comment, and 11 came from a concurrent run after it.
  def listing
    response([listed(7, 'shaka-agent'), listed(8, 'someone'), listed(9, 'shaka-agent', 'Plain note'),
              listed(10, 'shaka-agent'), listed(11, 'shaka-agent')])
  end

  def test_posts_a_new_comment_and_deletes_only_this_accounts_earlier_ones
    github = client(snapshot_response, stored(expected_body), response({ 'login' => 'shaka-agent' }),
                    listing, ['', '', STATUS.new(0)])

    result = github.squash_comment(head: HEAD, message: squash_message)

    assert_equal({ 'deleted' => [7], 'headline' => 'T (#42)' }, result.slice('deleted', 'headline'))
    verify_posted_blocks
  end

  def test_backticks_in_the_body_cannot_close_its_copy_block
    message = Shaka::SquashMessage.new({ 'title' => 'T', 'body' => "#{'a' * 72} ``` #{'b' * 72}" }, number: 42)
    body = Shaka::GitHub.new('owner/repo', 42).send(:squash_comment_body, HEAD, message)

    assert_includes body, "````text\n#{'a' * 72}\n```\n#{'b' * 72}\n````"
  end

  def test_refuses_a_moved_head_before_posting
    github = client(snapshot_response(head: 'c' * 40))

    assert_raises(Shaka::Error) { github.squash_comment(head: HEAD, message: squash_message) }
    assert_equal 1, @calls.length
  end

  private

  def verify_posted_blocks
    assert_equal ['repos/owner/repo/issues/comments/7', 'DELETE'], @calls.last[0].values_at(2, 4)
    posted = JSON.parse(@calls[1][1]).fetch('body')
    assert posted.start_with?(MARK)
    assert_includes posted, "```text\nT (#42)\n```"
    assert_includes posted, "```text\nB\n```"
  end
end

class MergeSquashMessageTest < Minitest::Test
  include MergeFixtures

  def squash_message = Shaka::SquashMessage.new({ 'title' => 'T', 'body' => 'B' }, number: 42)

  def test_merge_sends_the_squash_message_when_given_one
    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17, squash_message:)

    query, variables = @client.mutations.fetch(0)
    assert_includes query, 'commitHeadline: $headline'
    assert_equal({ 'headline' => 'T (#42)', 'body' => 'B' }, variables.slice('headline', 'body'))
    assert_equal 'applied', result.fetch('squash_message')
  end

  def test_merge_without_a_message_keeps_the_repository_default
    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    query, variables = @client.mutations.fetch(0)
    refute_includes query, 'commitHeadline'
    refute variables.key?('body')
    refute result.key?('squash_message')
  end

  def test_a_merge_queue_reports_that_the_message_was_not_applied
    entry = queue_entry(position: 1)
    ready = snapshot.merge('isMergeQueueEnabled' => true)
    @client.snapshots = [ready, ready, ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => entry)]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17, squash_message:)

    assert_equal 'not_applied_merge_queue', result.fetch('squash_message')
  end

  def test_an_already_queued_pull_request_reports_that_the_message_was_not_applied
    entry = queue_entry(position: 1)
    @client.snapshots = [snapshot.merge('isMergeQueueEnabled' => true, 'isInMergeQueue' => true,
                                        'mergeQueueEntry' => entry)]

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17, squash_message:)

    assert_equal 'not_applied_merge_queue', result.fetch('squash_message')
    assert_empty @client.mutations
  end
end
