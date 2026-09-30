# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'claim_helpers'

class ClaimTrackerTest < Minitest::Test
  include ClaimHelpers

  def test_a_tracker_key_matches_the_lowercased_branch_its_tracker_generates
    heads = "aaa\trefs/heads/alex/eng-123-fix-search\n" \
            "bbb\trefs/heads/alex/eng-1234-other\n"
    result = claim('ENG-123', prs: [], branches: heads)

    assert result.fetch('collision')
    assert_equal 'ENG-123', result.fetch('query')
    assert_equal ['alex/eng-123-fix-search'], result.fetch('branches')
  end

  def test_a_tracker_key_matches_a_lowercased_branch_through_the_seam_template
    result = claim('ENG-123', prs: [], branches: "aaa\trefs/heads/feature/eng-123/fix\n",
                              branch_name: 'feature/{issue}/{description}')

    assert_equal ['feature/eng-123/fix'], result.fetch('branches')
  end

  def test_accepts_a_jira_key_whose_project_has_an_underscore
    assert_equal 'MY_PROJ-12', claim('MY_PROJ-12', prs: [], branches: '').fetch('query')
  end

  def test_a_tracker_branch_name_is_reported_in_place_of_the_template
    result = claim('ENG-123', prs: [], branches: '', branch_name: 'feature/{issue}/{description}',
                              tracker_branch: 'alex/eng-123-fix-search')

    refute result.fetch('collision')
    assert_equal 'alex/eng-123-fix-search', result.fetch('branch_name')
  end

  def test_an_existing_tracker_branch_is_a_collision_even_without_the_key_in_its_name
    result = claim('ENG-123', prs: [], branches: "aaa\trefs/heads/alex/fix-search\n",
                              tracker_branch: 'alex/fix-search')

    assert result.fetch('collision')
    assert_equal ['alex/fix-search'], result.fetch('branches')
  end

  def test_cli_rejects_a_tracker_branch_git_would_refuse
    status = nil
    _stdout, stderr = capture_io do
      status = Shaka::Claim.run(['ENG-123', '--branch', 'alex/bad..name'], runner: runner(prs: [], branches: ''))
    end

    assert_equal 1, status
    assert_includes stderr, '--branch must be a valid Git branch name'
  end

  def test_cli_reports_a_valid_tracker_branch
    stdout, status = capture_cli(['ENG-123', '--branch', 'alex/eng-123-fix-search'], prs: [], branches: '')

    assert_equal 0, status
    assert_equal 'alex/eng-123-fix-search', JSON.parse(stdout).fetch('branch_name')
  end
end
