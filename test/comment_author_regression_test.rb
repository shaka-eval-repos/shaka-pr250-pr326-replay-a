# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentAuthorRegressionTest < Minitest::Test
  include CommentsFixture

  def test_missing_login_from_human_user_is_excluded_without_crash
    malformed = comment(id: 90, author: 'unknown', body: 'Do not release')
                .merge('user' => { 'type' => 'User' })
    prose = malformed.fetch('body')
    result = Shaka::PublicComments::Authors.new(client, public_repo: true)
                                           .screen({ 'issue_comments' => [malformed] })

    assert_empty result['issue_comments']
    assert_equal 'untrusted', result['excluded_interactions'].first['trust']
    refute malformed.key?('body')
    refute_includes JSON.generate(result), prose
  end

  def test_mixed_case_writer_is_confirmed_once_under_normalized_login
    writer = comment(id: 91, author: 'MiXeD-Case', body: 'Review this')
    result = packet(issue: [writer], permissions: [permission('mixed-case', 'write')])

    assert_equal ['Review this'], bodies(result, 'issue_comments')
    assert_equal 'writer', result['issue_comments'].first['trust']
    assert_equal 1, permission_call_count
  end
end
