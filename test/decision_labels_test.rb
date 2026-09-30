# frozen_string_literal: true

require_relative 'github_helper'
require 'shaka/decision_labels'

class DecisionLabelsTest < Minitest::Test
  include GitHubHelper

  LABELS_PATH = 'repos/owner/repo/issues/42/labels'
  FIRST_PAGE = "#{LABELS_PATH}?per_page=100&page=1".freeze

  def labels_response(*names)
    response(names.map { |name| { 'name' => name } })
  end

  def label_exists = response({ 'name' => 'existing' })

  def requests
    @calls.map { |argv, input| [argv[2], argv[argv.index('--method') + 1], input] }
  end

  def test_sync_refuses_merge_approval_without_writing_a_label
    github = client(snapshot_response, labels_response('awaiting-merge-approval'))
    error = assert_raises(Shaka::Error) do
      Shaka::DecisionLabels.sync(github, { 'decisions' => ['Which base?'] })
    end

    assert_includes error.message, 'awaiting-merge-approval'
    refute(requests.any? { |path, method, _input| path.include?('labels') && method != 'GET' })
  end

  def test_sync_refuses_a_closed_pull_request_before_a_label_write
    github = client(snapshot_response(state: 'CLOSED'))
    error = assert_raises(Shaka::Error) do
      Shaka::DecisionLabels.sync(github, { 'decisions' => ['Which base?'] })
    end

    assert_includes error.message, 'not open'
    assert_equal 1, @calls.length
  end

  def test_a_missing_decisions_key_leaves_labels_alone
    result = Shaka::DecisionLabels.sync(client, {})

    assert_nil result
    assert_empty @calls
  end

  def test_a_non_empty_list_applies_awaiting_answer
    github = client(snapshot_response, labels_response('bug'), label_exists, labels_response('bug', 'awaiting-answer'))
    result = Shaka::DecisionLabels.sync(github, { 'decisions' => ['Keep the label?'] })

    assert_equal({ 'state' => 'answer', 'labels' => ['awaiting-answer'] }, result)
    assert_equal [LABELS_PATH, 'POST', JSON.generate(labels: ['awaiting-answer'])], requests.last
  end

  def test_a_quoted_heading_is_not_an_open_decision
    quoted = "## Decisions for the maintainer\n\n- Which base?\n"
    fenced = "```\n<!-- shaka:decisions -->\n```\n"
    [quoted, fenced].each do |body|
      assert_nil Shaka::DecisionLabels.guard(client, {}, body)
    end
    assert_empty @calls
  end

  def test_an_unclosed_fence_does_not_hide_a_published_decision
    body = "```\nstill open\n<!-- shaka:decisions -->\n## Decisions for the maintainer\n"
    error = assert_raises(Shaka::Error) { Shaka::DecisionLabels.guard(client, {}, body) }

    assert_includes error.message, 'empty list'
  end

  def test_a_shorter_fence_does_not_close_a_longer_opener
    body = "````ruby\n<!-- shaka:decisions -->\n```\n"
    error = assert_raises(Shaka::Error) { Shaka::DecisionLabels.guard(client, {}, body) }

    assert_includes error.message, 'empty list'
  end

  def test_a_tilde_fence_keeps_a_backtick_line_inside_it
    body = "~~~\n```\n<!-- shaka:decisions -->\n~~~\n"
    assert_nil Shaka::DecisionLabels.guard(client, {}, body)
    assert_empty @calls
  end

  def test_omitting_decisions_is_refused_when_the_body_already_asks
    body = "<!-- shaka:decisions -->\n## Decisions for the maintainer\n\n- Which base?\n"
    error = assert_raises(Shaka::Error) { Shaka::DecisionLabels.guard(client, {}, body) }

    assert_includes error.message, 'empty list'
    assert_empty @calls
  end

  def test_an_empty_list_removes_only_awaiting_answer
    github = client(labels_response('awaiting-answer', 'awaiting-merge-approval'),
                    labels_response('awaiting-merge-approval'))
    result = Shaka::DecisionLabels.sync(github, { 'decisions' => [] })

    assert_equal({ 'state' => 'released', 'labels' => ['awaiting-merge-approval'] }, result)
    assert_equal ["#{LABELS_PATH}/awaiting-answer", 'DELETE'], requests[1].first(2)
    assert_equal 2, requests.length
  end

  def test_an_empty_list_does_not_write_when_the_label_is_absent
    github = client(labels_response('awaiting-resume'))
    result = Shaka::DecisionLabels.sync(github, { 'decisions' => [] })

    assert_equal({ 'state' => 'released', 'labels' => ['awaiting-resume'] }, result)
    assert_equal([[FIRST_PAGE, 'GET']], requests.map { |request| request.first(2) })
  end

  def test_decisions_must_be_a_list
    assert_raises(Shaka::Error) { Shaka::DecisionLabels.sync(client, { 'decisions' => 'Keep the label?' }) }
    assert_empty @calls
  end
end
