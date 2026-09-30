# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentVisibilityTest < Minitest::Test
  include CommentsFixture

  def test_internal_repo_does_not_apply_public_author_screen
    internal = comment(id: 15, author: 'enterprise-reader', body: 'Internal task data')
    result = packet(issue: [internal], visibility: 'internal')

    assert_equal 'internal', result['visibility']
    assert_equal [internal['body']], bodies(result, 'issue_comments')
    assert_equal 0, permission_call_count
  end

  def test_missing_explicit_visibility_stops_before_comment_read
    error = assert_raises(Shaka::Error) { packet(visibility: nil) }

    assert_match(/visibility is unavailable/, error.message)
  end

  def test_internal_to_public_visibility_change_discards_packet
    internal = comment(id: 16, author: 'enterprise-reader', body: 'Read before visibility changed')
    github = client(snapshot_response, repository_response('internal'), response([internal]),
                    response([]), response([]), thread_response([]), snapshot_response,
                    repository_response('public'))

    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/visibility changed/, error.message)
  end
end
