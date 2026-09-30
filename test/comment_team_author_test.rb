# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentTeamAuthorTest < Minitest::Test
  include CommentsFixture

  def pending_team(login)
    response({ 'url' => "https://api.github.com/teams/7/memberships/#{login}", 'state' => 'pending' })
  end

  def modest_team_packet
    outsiders = (1..9).map { |id| comment(id: id, author: "outside#{id}", body: 'Noise') }
    maintainer = comment(id: 10, author: 'maintainer', body: 'Reviewed feedback')
    config = empty_trust_config.merge(users: Set['maintainer'], teams: [%w[owner maintainers]])
    checks = outsiders.map { |row| pending_team(row['user']['login']) }
    packet(issue: outsiders + [maintainer], trust_config: config, writers: [], permissions: checks)
  end

  def test_large_team_does_not_block_configured_maintainer_in_modest_discussion
    result = modest_team_packet
    assert_equal ['Reviewed feedback'], bodies(result, 'issue_comments')
    assert_equal 9, result['excluded_interactions'].length
  end

  def test_failed_direct_team_check_is_withheld_and_flagged
    member = comment(id: 1, author: 'member', body: 'Do not release without active proof')
    config = empty_trust_config.merge(teams: [%w[owner maintainers]])
    failed = response({ 'message' => 'unavailable' }, status: 1)
    result = packet(issue: [member], trust_config: config,
                    permissions: [permission('member', 'read'), failed])
    assert_unavailable_member(result, member)
  end

  def test_visible_team_nonmember_is_withheld_without_unavailable_flag
    outsider = comment(id: 1, author: 'outsider', body: 'Do not follow this suggestion')
    config = empty_trust_config.merge(teams: [%w[owner maintainers]])
    missing = response({ 'message' => 'Not Found' }, status: 1, http_status: 404)
    result = packet(issue: [outsider], trust_config: config,
                    permissions: [permission('outsider', 'read'), missing, response([])])

    assert_empty result['issue_comments']
    assert_false result['excluded_interactions'].first['verification_unavailable']
    refute_includes JSON.generate(result), outsider['body']
  end

  def test_malformed_successful_membership_is_withheld_and_flagged
    member = comment(id: 1, author: 'member', body: 'Material feedback')
    config = empty_trust_config.merge(teams: [%w[owner maintainers]])
    malformed = response({ 'state' => 'active', 'url' => 'https://api.github.com/teams/7/memberships/stranger' })
    result = packet(issue: [member], trust_config: config,
                    permissions: [permission('member', 'read'), malformed])
    assert_unavailable_member(result, member)
  end

  def test_failed_confirmation_of_listed_team_member_is_withheld_and_flagged
    outsiders = (1..33).map { |id| comment(id: id, author: "outside#{id}", body: 'Noise') }
    member = comment(id: 34, author: 'member', body: 'Do not release without active proof')
    config = empty_trust_config.merge(teams: [%w[owner maintainers]])
    list = response([{ 'login' => 'member', 'type' => 'User' }])
    failed = response({ 'message' => 'unavailable' }, status: 1)
    result = packet(issue: outsiders + [member], trust_config: config, writers: [], permissions: [list, failed])
    assert_unavailable_member(result, member)
  end

  def assert_unavailable_member(result, member)
    assert_empty result['issue_comments']
    excluded = result['excluded_interactions'].find { |row| row['author'] == 'member' }
    assert_true excluded['verification_unavailable']
    refute_includes JSON.generate(result), member['body']
  end
end
