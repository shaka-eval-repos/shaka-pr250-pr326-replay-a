# frozen_string_literal: true

require 'tmpdir'
require_relative 'comments_fixture'

class CommentConfigScreeningTest < Minitest::Test
  include CommentsFixture

  def default_ref
    response({ 'data' => { 'repository' => { 'defaultBranchRef' => { 'target' => { 'oid' => BASE } } } } })
  end

  def repo_config
    text = "trusted_teams: [maintainers]\n"
    object = { '__typename' => 'Blob', 'text' => text, 'byteSize' => text.bytesize,
               'isBinary' => false, 'isTruncated' => false }
    response({ 'data' => { 'repository' => { 'object' => object } } })
  end

  def team_membership
    response({ 'url' => 'https://api.github.com/teams/7/memberships/member', 'state' => 'active' })
  end

  def configured_client(bot, member)
    responses = [snapshot_response, repository_response('public'), default_ref, repo_config]
    responses += [response([bot, member]), response([]), response([]), thread_response([])]
    responses += [permission('member', 'read'), team_membership]
    client(*responses, snapshot_response, default_ref, repository_response('public'))
  end

  def test_real_loader_combines_machine_bot_and_repository_team_trust
    Dir.mktmpdir do |dir|
      assert_configured_screening(configured_packet(dir))
    end
  end

  def configured_packet(dir)
    path = File.join(dir, 'machine.yml')
    File.write(path, "trusted_bots: [review-bot]\n")
    bot = comment(id: 95, author: 'review-bot[bot]', body: 'Bot finding')
          .merge('user' => { 'login' => 'review-bot[bot]', 'type' => 'Bot' })
    member = comment(id: 96, author: 'member', body: 'Team finding')
    Shaka::PublicComments::Reader.new(configured_client(bot, member), machine_path: path).call(expected_head: HEAD)
  end

  def assert_configured_screening(result)
    assert_equal ['Bot finding', 'Team finding'], bodies(result, 'issue_comments')
    assert_equal(%w[configured_bot team], result['issue_comments'].map { |row| row['trust'] })
    assert_equal(%w[machine repository], result['trust_sources'].map { |source| source['scope'] })
  end
end
