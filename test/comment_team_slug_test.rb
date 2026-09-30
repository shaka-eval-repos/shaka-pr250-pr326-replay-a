# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentTeamSlugTest < Minitest::Test
  include CommentsFixture

  def test_team_slug_may_contain_underscores
    settings = Shaka::PublicComments::TrustSettings.new('owner/repo')
    result = settings.parse("trusted_teams: [core_team]\n", scope: 'repository')

    assert_equal [%w[owner core_team]], result[:teams]
  end
end
