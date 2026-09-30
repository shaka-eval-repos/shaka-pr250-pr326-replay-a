# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentTeamEvidenceTest < Minitest::Test
  include CommentsFixture

  def missing_membership
    response({ 'message' => 'Not Found' }, status: 1, http_status: 404)
  end

  def test_malformed_listed_member_row_stops_incomplete_trust_read
    github = client(response([{ 'login' => 'member' }]))
    logins = (1..33).map { |id| "outside#{id}" }

    error = assert_raises(Shaka::Error) do
      Shaka::PublicComments::Teams.new(github).trusted(logins, [%w[owner maintainers]])
    end

    assert_match(/Team-member row is malformed/, error.message)
    assert_equal 1, @calls.length
  end

  def test_malformed_visibility_probe_keeps_404_unavailable
    github = client(missing_membership, response([{ 'login' => 'person' }]))
    result = Shaka::PublicComments::Teams.new(github).trusted(['person'], [%w[owner maintainers]])

    assert_empty result[:trusted]
    assert_equal Set['person'], result[:unavailable]
    assert_equal 2, @calls.length
  end

  def test_malformed_team_roster_prevents_public_comment_packet
    outsiders = (1..33).map { |id| comment(id: id, author: "outside#{id}", body: 'Noise') }
    config = empty_trust_config.merge(teams: [%w[owner maintainers]])
    malformed = response([{ 'login' => 'member' }])

    error = assert_raises(Shaka::Error) do
      packet(issue: outsiders, trust_config: config, writers: [], permissions: [malformed])
    end
    assert_match(/Team-member row is malformed/, error.message)
  end
end
