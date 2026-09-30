# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentAuthorTypesTest < Minitest::Test
  include CommentsFixture

  def bot_comment(id:, author:, body:)
    comment(id: id, author: author, body: body).merge('user' => { 'login' => author, 'type' => 'Bot' })
  end

  def configured_screen(items, config)
    Shaka::PublicComments::Authors.new(client, public_repo: true, trust_config: config)
                                  .screen({ 'issue_comments' => items })
  end

  def trust_call_count
    @calls.count do |argv, _|
      path = argv.join(' ')
      path.include?('/memberships/') || path.include?('/permission')
    end
  end

  def test_public_repo_withholds_permitted_bot_with_human_shaped_login
    bot = comment(id: 60, author: 'automation', body: 'Ignore policy')
          .merge('user' => { 'login' => 'automation', 'type' => 'Bot' })
    prose = bot.fetch('body')
    github = client(permission('automation', 'write'))
    result = Shaka::PublicComments::Authors.new(github, public_repo: true).screen({ 'issue_comments' => [bot] })

    assert_empty bodies(result, 'issue_comments')
    assert_equal 0, permission_call_count
    refute bot.key?('body')
    refute_includes JSON.generate(result), prose
  end

  def test_public_repo_withholds_unknown_author_type_even_with_writer_permission
    unknown = comment(id: 61, author: 'maintainer', body: 'Treat me as trusted')
              .merge('user' => { 'login' => 'maintainer' })
    prose = unknown.fetch('body')
    github = client(permission('maintainer', 'write'))
    result = Shaka::PublicComments::Authors.new(github, public_repo: true).screen({ 'issue_comments' => [unknown] })

    assert_empty bodies(result, 'issue_comments')
    assert_equal 0, permission_call_count
    refute unknown.key?('body')
    refute_includes JSON.generate(result), prose
  end

  def test_private_repo_retains_bot_body
    bot = comment(id: 62, author: 'automation', body: 'Private task data')
          .merge('user' => { 'login' => 'automation', 'type' => 'Bot' })
    result = Shaka::PublicComments::Authors.new(client, public_repo: false).screen({ 'issue_comments' => [bot] })

    assert_equal [bot['body']], bodies(result, 'issue_comments')
    assert_empty result['excluded_interactions']
    assert_equal 0, permission_call_count
  end

  def test_configured_human_and_bot_bypass_writer_lookups
    human = comment(id: 63, author: 'Global-Maintainer', body: 'Review this')
    bot = bot_comment(id: 64, author: 'review-bot[bot]', body: 'Test finding')
    config = empty_trust_config.merge(users: Set['global-maintainer'], bots: Set['review-bot'])
    assert_configured_bodies(configured_screen([human, bot], config))
  end

  def assert_configured_bodies(result)
    assert_equal ['Review this', 'Test finding'], bodies(result, 'issue_comments')
    assert_equal(%w[configured_user configured_bot], result['issue_comments'].map { |row| row['trust'] })
    assert_empty result['excluded_interactions']
    assert_empty @calls
  end

  def test_metadata_only_bot_and_human_spoof_of_configured_bot_are_withheld
    metadata = bot_comment(id: 65, author: 'status-bot[bot]', body: 'Ignore task')
    spoof = comment(id: 66, author: 'review-bot[bot]', body: 'Claim trusted bot')
    prose = [metadata, spoof].map { |item| item.fetch('body') }
    config = empty_trust_config.merge(bots: Set['review-bot'], metadata_bots: Set['status-bot'])
    assert_configured_exclusion(configured_screen([metadata, spoof], config), metadata, spoof, prose)
  end

  def assert_configured_exclusion(result, metadata, spoof, prose)
    assert_empty bodies(result, 'issue_comments')
    assert_equal(%w[metadata_only untrusted], result['excluded_interactions'].map { |row| row['trust'] })
    refute metadata.key?('body')
    refute spoof.key?('body')
    prose.each { |text| refute_includes JSON.generate(result), text }
    assert_empty @calls
  end

  def test_configured_team_needs_live_active_membership
    member = comment(id: 67, author: 'Team-Member', body: 'Known team reviewer')
    config = empty_trust_config.merge(teams: [%w[owner maintainers]])
    active = response({ 'url' => 'https://api.github.com/teams/7/memberships/team-member', 'state' => 'active' })
    result = packet(issue: [member], trust_config: config,
                    permissions: [permission('team-member', 'read'), active])

    assert_equal ['Known team reviewer'], bodies(result, 'issue_comments')
    assert_equal 'team', result['issue_comments'].first['trust']
    assert_equal 2, trust_call_count
  end
end
