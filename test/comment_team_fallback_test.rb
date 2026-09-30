# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentTeamFallbackTest < Minitest::Test
  include CommentsFixture

  def logins(count)
    (1..count).map { |id| "outside#{id}" }
  end

  def oversized_pages
    members = Array.new(100) { |id| { 'login' => "person#{id}", 'type' => 'User' } }
    Array.new(11) { response(members) }
  end

  def pending(login)
    response({ 'url' => "https://api.github.com/teams/7/memberships/#{login}", 'state' => 'pending' })
  end

  def active(login)
    response({ 'url' => "https://api.github.com/teams/7/memberships/#{login}", 'state' => 'active' })
  end

  def all_member_client(authors)
    roster = authors.map { |login| { 'login' => login, 'type' => 'User' } }
    client(response(roster), *authors.map { |login| active(login) })
  end

  def test_confirmed_authors_skip_later_team_lists
    authors = logins(33)
    github = all_member_client(authors)

    result = Shaka::PublicComments::Teams.new(github).trusted(authors, [%w[owner first], %w[owner second]])
    assert_equal Set.new(authors), result[:trusted]
    assert_equal 34, @calls.length
  end

  def test_modest_discussion_uses_direct_checks_without_listing_large_team
    authors = logins(9)
    github = client(*authors.map { |login| pending(login) })

    assert_empty Shaka::PublicComments::Teams.new(github).trusted(authors, [%w[owner maintainers]])[:trusted]
    assert_equal 9, @calls.length
    assert(@calls.all? { |argv, _| argv[2].include?('/memberships/') })
  end

  def test_oversized_listing_falls_back_to_bounded_direct_checks
    authors = logins(40)
    github = client(*oversized_pages, *authors.map { |login| pending(login) })

    result = Shaka::PublicComments::Teams.new(github).trusted(authors, [%w[owner maintainers]])
    assert_equal({ trusted: Set.new, unavailable: Set.new }, result)
    assert_equal 51, @calls.length
  end

  def test_oversized_listing_stops_before_excessive_direct_fallback
    github = client(*oversized_pages)
    error = assert_raises(Shaka::Error) do
      Shaka::PublicComments::Teams.new(github).trusted(logins(101), [%w[owner maintainers]])
    end

    assert_match(/list evidence is unavailable/, error.message)
    assert_equal 11, @calls.length
  end

  def test_listed_membership_confirmations_have_one_aggregate_cap
    authors = logins(101)
    github = client(*listed_member_pages(authors))

    error = assert_raises(Shaka::Error) do
      Shaka::PublicComments::Teams.new(github).trusted(authors, [%w[owner maintainers]])
    end

    assert_match(/100 checks/, error.message)
    assert_equal 2, @calls.length
  end

  def listed_member_pages(authors)
    rows = authors.map { |login| { 'login' => login, 'type' => 'User' } }
    [response(rows.first(100)), response(rows.last(1))]
  end
end
