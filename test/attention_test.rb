# frozen_string_literal: true

require_relative 'github_helper'
require 'shaka/attention'

class AttentionTest < Minitest::Test
  include GitHubHelper

  LABELS_PATH = 'repos/owner/repo/issues/42/labels'
  REPO_LABELS = 'repos/owner/repo/labels'
  FIRST_PAGE = "#{LABELS_PATH}?per_page=100&page=1".freeze

  def labels_response(*names)
    response(names.map { |name| { 'name' => name } })
  end

  def call(state, *responses)
    Shaka::Attention.new(client(*responses)).call(state: state)
  end

  def requests
    @calls.map { |argv, input| [argv[2], argv[argv.index('--method') + 1], input] }
  end

  def label_exists = response({ 'name' => 'existing' })
  def label_missing = response({ 'message' => 'Not Found' }, status: 1, http_status: 404)

  def test_answer_replaces_merge_approval_with_one_label
    result = call('answer', snapshot_response, labels_response('bug', 'awaiting-merge-approval'), label_exists,
                  labels_response('bug'), labels_response('bug', 'awaiting-answer'))

    assert_equal({ 'state' => 'answer', 'labels' => ['awaiting-answer'] }, result)
    assert_equal ["#{LABELS_PATH}/awaiting-merge-approval", 'DELETE'], requests[3].first(2)
    assert_equal [LABELS_PATH, 'POST', JSON.generate(labels: ['awaiting-answer'])], requests[4]
  end

  def test_resume_replaces_answer
    result = call('resume', snapshot_response, labels_response('awaiting-answer'), label_exists,
                  labels_response, labels_response('awaiting-resume'))

    assert_equal({ 'state' => 'resume', 'labels' => ['awaiting-resume'] }, result)
    assert_equal ["#{LABELS_PATH}/awaiting-answer", 'DELETE'], requests[3].first(2)
  end

  def test_a_missing_label_is_created_with_its_color_and_description
    call('merge', snapshot_response, labels_response, label_missing,
         response({ 'name' => 'awaiting-merge-approval' }), labels_response('awaiting-merge-approval'))

    assert_equal ["#{REPO_LABELS}/awaiting-merge-approval", 'GET'], requests[2].first(2)
    path, method, input = requests[3]
    assert_equal [REPO_LABELS, 'POST'], [path, method]
    assert_equal({ 'name' => 'awaiting-merge-approval', 'color' => '8250DF',
                   'description' => Shaka::Attention::DESCRIPTIONS.fetch('awaiting-merge-approval') },
                 JSON.parse(input))
  end

  def test_an_existing_repository_label_is_applied_without_creating
    result = call('answer', snapshot_response, labels_response, label_exists, labels_response('awaiting-answer'))

    assert_equal({ 'state' => 'answer', 'labels' => ['awaiting-answer'] }, result)
    assert_equal(%w[GET GET POST], requests.drop(1).map { |request| request[1] })
  end

  def test_a_caller_who_cannot_create_labels_still_applies_one
    forbidden = response({ 'message' => 'Forbidden' }, status: 1, http_status: 403)
    result = call('answer', snapshot_response, labels_response, label_missing, forbidden,
                  labels_response('awaiting-answer'))

    assert_equal({ 'state' => 'answer', 'labels' => ['awaiting-answer'] }, result)
    assert_equal [LABELS_PATH, 'POST'], requests[4].first(2)
  end

  def test_merge_keeps_an_existing_label_without_writing
    result = call('merge', snapshot_response, labels_response('awaiting-merge-approval'))

    assert_equal({ 'state' => 'merge', 'labels' => ['awaiting-merge-approval'] }, result)
    assert_equal([[FIRST_PAGE, 'GET']], requests.drop(1).map { |request| request.first(2) })
  end

  def test_none_clears_both_labels_even_after_the_pr_closes
    result = call('none', labels_response('awaiting-answer', 'awaiting-merge-approval', 'bug'),
                  labels_response('awaiting-merge-approval', 'bug'), labels_response('bug'))

    assert_equal({ 'state' => 'none', 'labels' => [] }, result)
    assert_equal(%w[GET DELETE DELETE], requests.map { |request| request[1] })
  end

  def test_none_clears_a_label_on_the_second_page
    first_page = labels_response(*(1..100).map { |index| "label-#{index}" })
    result = call('none', first_page, labels_response('awaiting-answer'), labels_response)

    assert_equal({ 'state' => 'none', 'labels' => [] }, result)
    assert_equal ["#{LABELS_PATH}?per_page=100&page=2", 'GET'], requests[1].first(2)
    assert_equal ["#{LABELS_PATH}/awaiting-answer", 'DELETE'], requests[2].first(2)
  end

  def test_a_failed_label_write_is_an_error
    error = assert_raises(Shaka::Error) do
      call('answer', snapshot_response, labels_response, label_exists, response({}, status: 1))
    end

    assert_match(/gh api .*labels failed/, error.message)
  end

  def test_setting_a_label_requires_an_open_pull_request
    error = assert_raises(Shaka::Error) { call('merge', snapshot_response(state: 'MERGED')) }

    assert_match(/not open/, error.message)
    assert_equal 1, @calls.length
  end

  def test_rejects_an_unknown_state_before_any_request
    assert_raises(Shaka::Error) { call('approved') }
    assert_empty @calls
  end

  def test_command_rejects_an_unknown_state
    command = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
    _output, error, status = Open3.capture3(command, 'attention', 'owner/repo', '1', '--state', 'approved')

    refute_predicate status, :success?
    assert_match(/invalid argument: --state approved/, error)
  end
end
