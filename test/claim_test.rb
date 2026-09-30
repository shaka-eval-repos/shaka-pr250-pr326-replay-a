# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'shaka/claim'
require_relative 'claim_helpers'

class ClaimTest < Minitest::Test
  include ClaimHelpers

  PR_110 = { 'number' => 110, 'title' => 'Restore lines', 'url' => 'https://example/110',
             'headRefName' => 'jg-claude/36-restore-workflow-lines' }.freeze
  PR_111 = { 'number' => 111, 'title' => 'Dup', 'url' => 'https://example/111',
             'headRefName' => 'jg-codex/36-restore' }.freeze
  HEADS_36 = "aaa\trefs/heads/jg-claude/36-restore-workflow-lines\n" \
             "bbb\trefs/heads/jg-codex/36-restore-workflow-judgment\n" \
             "ccc\trefs/heads/jg-codex/136-unrelated\n"

  def test_reports_open_pull_requests_and_matching_remote_branches_as_a_collision
    result = claim('36', prs: [PR_110], branches: HEADS_36)

    assert result.fetch('collision')
    assert_equal 110, result.fetch('pull_requests').first.fetch('number')
    assert_equal %w[jg-claude/36-restore-workflow-lines jg-codex/36-restore-workflow-judgment],
                 result.fetch('branches')
  end

  def test_a_clear_search_is_not_a_collision
    result = claim('116', prs: [], branches: "aaa\trefs/heads/jg-cursor/115-walkthrough-pin-links\n")

    refute result.fetch('collision')
    assert_empty result.fetch('pull_requests')
    assert_empty result.fetch('branches')
  end

  def test_a_branch_prefix_hit_without_an_open_pr_is_still_a_collision
    result = claim('36', prs: [], branches: "aaa\trefs/heads/jg-cursor/36-restore-workflow-judgment\n")

    assert result.fetch('collision')
    assert_equal ['jg-cursor/36-restore-workflow-judgment'], result.fetch('branches')
  end

  def test_a_seam_template_matches_a_repository_specific_layout
    heads = "aaa\trefs/heads/feature/36/restore-lines\n" \
            "bbb\trefs/heads/feature/136/unrelated\n"
    result = claim('36', prs: [], branches: heads, branch_name: 'feature/{issue}/{description}')

    assert result.fetch('collision')
    assert_equal ['feature/36/restore-lines'], result.fetch('branches')
    assert_equal 'feature/{issue}/{description}', result.fetch('branch_name')
  end

  def test_refuses_a_work_item_that_is_neither_a_number_nor_a_tracker_key
    %w[restore ENG- -123 ENG-0 1ENG-2 _ENG-2].each do |query|
      error = assert_raises(Shaka::Error) { claim(query, prs: [], branches: '') }

      assert_includes error.message, 'issue number or tracker key', query
    end
  end

  def test_cli_prints_collision_json
    stdout, status = capture_cli(['36'], prs: [PR_111], branches: HEADS_36)

    assert_equal 0, status
    assert JSON.parse(stdout).fetch('collision')
  end

  def test_asks_github_for_more_than_the_default_page_of_pull_requests
    seen = pr_argv(prs: [], branches: '')

    assert_equal '1000', seen.fetch(seen.index('--limit') + 1)
  end

  private

  def pr_argv(prs:, branches:)
    seen = nil
    inner = runner(prs: prs, branches: branches)
    wrapped = lambda do |argv, **|
      seen = argv if argv[1] == 'pr'
      inner.call(argv)
    end
    Shaka::Claim.new(query: '36', root: Dir.pwd, runner: wrapped, branch_name: nil).result
    seen
  end
end
