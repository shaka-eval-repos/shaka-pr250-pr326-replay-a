# frozen_string_literal: true

require_relative 'github_helper'

# Publication measures GitHub's rendering and refuses a wall of text before anything is written.
class GitHubProseLimitsTest < Minitest::Test
  include GitHubHelper

  WALL = Array.new(9) { "<p>Alpha #{Array.new(18, 'word').join(' ')} end.</p>" }.join("\n")

  def test_description_is_refused_before_the_pull_request_is_edited
    github = client(response({ 'id' => 1, 'body' => '', 'additions' => 4, 'deletions' => 2 }), html_response(WALL))

    error = assert_raises(Shaka::Error) { github.description(body: "Summary.\n") }

    assert_includes error.message, 'Description is hard to read'
    assert_equal 2, @calls.size
  end

  def test_walkthrough_is_refused_before_the_review_is_posted
    pull = { 'headRefOid' => HEAD, 'state' => 'OPEN', 'additions' => 4, 'deletions' => 2 }
    snapshot = response({ 'data' => { 'repository' => { 'pullRequest' => pull } } })
    github = client(snapshot, files_response, *gate_responses, html_response(WALL))

    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: WALKTHROUGH) }

    assert_includes error.message, 'Walkthrough is hard to read'
    refute(@calls.any? { |argv, _| argv.include?('POST') && argv.any? { |arg| arg.end_with?('/reviews') } })
  end
end
