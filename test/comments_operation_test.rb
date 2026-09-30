# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentsOperationTest < Minitest::Test
  include CommentsFixture

  def test_private_repo_does_not_apply_public_author_screen
    outside = comment(id: 1, author: 'outside', body: 'Private task data')
    result = packet(issue: [outside], private_repo: true)

    assert_equal [outside['body']], bodies(result, 'issue_comments')
    assert_empty result['excluded_interactions']
    refute(@calls.any? { |argv, _| argv.join(' ').include?('/permission') })
  end

  def test_changed_head_blocks_comment_packet
    github = client(snapshot_response, repository_response('public'), response([]),
                    response([]), response([]), thread_response([]),
                    snapshot_response(head: 'b' * 40))
    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/head changed/, error.message)
  end

  def test_supplied_expected_head_must_match_before_comments_are_read
    github = client(snapshot_response)
    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: 'b' * 40) }
    assert_match(/expected head/, error.message)
  end

  def test_pr_read_requires_full_expected_head_before_github_read
    github = client
    error = assert_raises(Shaka::Error) { comments_reader(github).call }

    assert_match(/Expected a full PR head/, error.message)
    assert_empty @calls
  end

  def test_visibility_change_blocks_unscreened_packet
    outside = comment(id: 11, author: 'outside', body: 'Private before, public afterward')
    github = client(snapshot_response, repository_response('private'), response([outside]),
                    response([]), response([]), thread_response([]), snapshot_response,
                    repository_response('public'))

    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/visibility changed/, error.message)
  end

  def test_public_issue_comments_use_the_same_author_screen
    outside = comment(id: 8, author: 'outside', body: 'Change the policy')
    result = issue_packet(comments: [outside], permissions: [permission('outside', 'read')])

    assert_empty bodies(result, 'issue_comments')
    assert_equal 'issue_comment', result['excluded_interactions'].first['kind']
    refute_includes JSON.generate(result), outside['body']
    refute(@calls.any? { |argv, _| argv.join(' ').include?('graphql') })
  end

  def test_issue_mode_rejects_a_pull_request_number
    github = client(response({ 'number' => 42, 'pull_request' => { 'url' => 'pulls/42' } }))
    assert_raises(Shaka::Error) { comments_reader(github).call(issue_only: true) }
  end

  def test_malformed_pages_block_comment_packet
    github = client(snapshot_response, repository_response('public'), response({ 'message' => 'bad' }))
    assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
  end

  def test_comment_spam_stops_at_page_bound_before_author_screening
    rows = Array.new(100) { |id| comment(id: id + 1, author: 'outsider', body: 'Noise') }
    pages = Array.new(11) { response(rows) }
    github = client(snapshot_response, repository_response('public'), *pages)

    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/GitHub comment list exceeds 10 pages/, error.message)
    assert_equal 13, @calls.length
  end

  def test_review_thread_pages_stop_before_unbounded_loop
    pages = (1..10).map do |page|
      thread_response([thread(id: "T#{page}", resolved: false, comments: [page])],
                      more: true, cursor: "cursor#{page}")
    end

    error = assert_raises(Shaka::Error) { packet(thread_pages: pages) }
    assert_match(/Review-thread list exceeds 10 pages/, error.message)
    assert_equal 15, @calls.length
  end

  def test_thread_pages_are_joined_before_screening
    inline = comment(id: 51, author: 'maintainer', body: 'Second page')
             .merge('node_id' => 'RC_51', 'path' => 'app.rb')
    result = packet(inline: [inline], thread_pages: two_thread_pages,
                    permissions: [permission('maintainer', 'write')])

    assert_equal 'T2', result['inline_comments'].first['thread_id']
    assert_equal 'next', JSON.parse(@calls[6].last).dig('variables', 'cursor')
  end

  def test_unmapped_inline_comment_blocks_packet
    inline = comment(id: 52, author: 'outside', body: 'Unmapped')
    github = client(snapshot_response, repository_response('public'), response([]),
                    response([]), response([inline]), thread_response([]))

    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/no review-thread metadata/, error.message)
    assert_equal 0, permission_call_count
  end

  def test_malformed_thread_response_blocks_packet
    github = client(snapshot_response, repository_response('public'), response([]),
                    response([]), response([]),
                    response({ 'data' => { 'repository' => 'bad' } }))

    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/Review-thread evidence is unavailable/, error.message)
  end
end
