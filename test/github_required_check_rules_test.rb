# frozen_string_literal: true

require_relative 'github_helper'

class GitHubRequiredCheckRulesTest < Minitest::Test
  include GitHubHelper

  PLAN_403 = ['{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}',
              'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)',
              STATUS.new(1)].freeze

  def test_reports_classic_protection_and_ruleset_contexts
    rules = [{ 'type' => 'pull_request' },
             { 'type' => 'required_status_checks',
               'parameters' => { 'required_status_checks' => [{ 'context' => 'validate' }] } }]
    github = client(base_rule_response(['ci']), response(rules))

    assert_equal %w[ci validate], github.configured_required_checks
    assert_equal ['gh', 'api', 'repos/owner/repo/rules/branches/main?per_page=100'], @calls.last.first.first(3)
  end

  def test_a_slash_in_the_base_branch_is_one_encoded_segment
    client(base_rule_response([], branch: 'release/1.x'), response([])).configured_required_checks

    assert_equal 'repos/owner/repo/rules/branches/release%2F1.x?per_page=100', @calls.last.first[2]
  end

  def test_an_unprotected_branch_requires_nothing
    assert_empty client(base_rule_response(nil), response([])).configured_required_checks
  end

  def test_a_plan_without_rulesets_requires_nothing_beyond_classic_protection
    assert_empty client(base_rule_response([]), PLAN_403).configured_required_checks
  end

  def test_other_ruleset_failures_are_not_treated_as_no_requirements
    forbidden = ['{"message":"Resource not accessible"}', 'gh: Resource not accessible (HTTP 403)', STATUS.new(1)]
    github = client(base_rule_response([]), forbidden)

    error = assert_raises(Shaka::Error) { github.configured_required_checks }
    assert_equal 403, error.http_status
  end

  def test_a_malformed_status_check_rule_is_refused_rather_than_read_as_empty
    [{ 'type' => 'required_status_checks' },
     { 'type' => 'required_status_checks', 'parameters' => { 'required_status_checks' => [{}] } }].each do |rule|
      github = client(base_rule_response([]), response([rule]))
      error = assert_raises(Shaka::Error) { github.configured_required_checks }
      assert_includes error.message, 'required_status_checks'
    end
  end

  def test_a_full_page_of_rules_is_refused_rather_than_truncated
    rules = Array.new(100) { { 'type' => 'pull_request' } }
    error = assert_raises(Shaka::Error) { client(base_rule_response([]), response(rules)).configured_required_checks }
    assert_includes error.message, 'rules'
  end

  private

  def base_rule_response(contexts, branch: 'main')
    rule = contexts && { 'requiredStatusCheckContexts' => contexts }
    response({ 'data' => { 'repository' => { 'pullRequest' => {
               'baseRefName' => branch, 'baseRef' => { 'refUpdateRule' => rule }
             } } } })
  end
end
