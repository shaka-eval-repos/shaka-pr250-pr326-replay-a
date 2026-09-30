# frozen_string_literal: true

require_relative 'test_helper'
require 'json'

class CliTest < Minitest::Test
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def test_help_explains_each_operation
    output, error, status = Open3.capture3(COMMAND, '--help')
    assert_predicate status, :success?, error
    %w[pr comments description reply resolve walkthrough merge recommendation checkpoint seam doctor
       enforcement repos prefix attention handoff --head --issue --content-file --key --comment --thread
       --ci-review-wait --ref --state].each { |token| assert_includes output, token }
  end

  def test_invalid_ci_review_wait_does_not_call_github
    without_github do |dir, sentinel|
      _output, error, status = run_offline(dir, '{}', 'merge', 'owner/repo', '1', '--ci-review-wait', 'auto')
      refute_predicate status, :success?, error
      refute_path_exists sentinel
    end
  end

  def test_missing_content_file_is_a_clear_error
    _output, error, status = Open3.capture3(COMMAND, 'description', 'owner/repo', '1',
                                            '--content-file', '/missing/shaka-content.json')
    refute_predicate status, :success?
    assert_includes error, 'shaka-content.json'
  end

  def test_recommendation_renders_without_calling_github
    without_github do |dir, sentinel|
      body = JSON.generate(value: 'Slow search.', scope: 'Small.', risk: 'Policy.',
                           model: 'gpt-example', effort: 'medium', reason: 'Fit.')
      output, error, status = run_offline(dir, body, 'recommendation')
      assert_predicate status, :success?, error
      assert_equal "Value: Slow search.\nScope: Small.\nRisk: Policy.\n" \
                   "Model: gpt-example\nEffort: medium\nReason: Fit.\n", output
      refute_path_exists sentinel
    end
  end

  def test_checkpoint_reports_when_matching_intake_can_proceed_without_github
    without_github do |dir, sentinel|
      body = JSON.generate(requested_model: 'gpt-5.6-terra', requested_effort: 'medium',
                           recommended_model: 'gpt-5.6-terra', recommended_effort: 'medium',
                           active_model: 'gpt-5.6-terra', active_effort: 'medium',
                           immediate_start: true, settings_available: true)
      output, error, status = run_offline(dir, body, 'checkpoint')
      assert_predicate status, :success?, error
      assert_equal({ 'status' => 'proceed' }, JSON.parse(output))
      refute_path_exists sentinel
    end
  end

  # A stub gh on PATH records any invocation, so "never contacts GitHub" is actually asserted.
  def without_github
    Dir.mktmpdir do |dir|
      sentinel = File.join(dir, 'called')
      File.write(File.join(dir, 'gh'), "#!/bin/sh\ntouch #{sentinel}\nexit 1\n")
      File.chmod(0o755, File.join(dir, 'gh'))
      yield dir, sentinel
    end
  end

  def run_offline(dir, body, *)
    path = File.join(dir, 'content.json')
    File.write(path, body)
    Open3.capture3({ 'PATH' => "#{dir}:#{ENV.fetch('PATH')}" }, COMMAND, *, '--content-file', path)
  end

  def test_a_reply_without_a_key_does_not_call_github
    without_github do |dir, sentinel|
      body = JSON.generate({ 'identity' => { 'agent' => 'Codex' }, 'summary' => 'Done.' })
      _output, error, status = run_offline(dir, body, 'reply', 'owner/repo', '1')
      refute_predicate status, :success?
      assert_includes error, 'key'
      refute_path_exists sentinel, 'the reply attempted a GitHub request without a key'
    end
  end

  def test_content_that_is_not_a_json_object_is_a_clear_error
    without_github do |dir, sentinel|
      _output, error, status = run_offline(dir, '[1, 2, 3]', 'walkthrough', 'owner/repo', '1',
                                           '--head', 'a' * 40)
      refute_predicate status, :success?
      assert_includes error, 'shaka: '
      refute_includes error, 'NoMethodError'
      refute_path_exists sentinel
    end
  end

  def test_invalid_operation_exits_without_a_github_call
    _output, error, status = Open3.capture3(COMMAND, 'unexpected', 'owner/repo', '1')
    refute_predicate status, :success?
    assert_includes error, 'Usage:'
  end

  def test_missing_walkthrough_file_is_a_clear_error
    _output, error, status = Open3.capture3(COMMAND, 'walkthrough', 'owner/repo', '1',
                                            '--head', 'a' * 40, '--body-file', '/missing/shaka-body.md')
    refute_predicate status, :success?
    assert_includes error, 'shaka:'
    assert_includes error, 'shaka-body.md'
  end

  def test_merge_without_head_does_not_call_github
    _output, error, status = Open3.capture3(COMMAND, 'merge', 'owner/repo', '1')
    refute_predicate status, :success?
    assert_includes error, 'head'
  end

  def test_pr_comment_reader_requires_an_expected_head
    _output, error, status = Open3.capture3(COMMAND, 'comments', 'owner/repo', '1')
    refute_predicate status, :success?
    assert_includes error, 'Expected a full PR head'
  end
end

class CliMergeRefTest < Minitest::Test
  def test_merge_without_ref_does_not_call_github
    Dir.mktmpdir do |dir|
      sentinel = File.join(dir, 'called')
      File.write(stub = File.join(dir, 'gh'), "#!/bin/sh\ntouch #{sentinel}\nexit 1\n")
      File.chmod(0o755, stub)
      args = ['merge', 'owner/repo', '1', '--head', 'a' * 40, '--base', 'main', '--walkthrough', '1']
      _output, error, status = Open3.capture3({ 'PATH' => "#{dir}:#{ENV.fetch('PATH')}" }, CliTest::COMMAND, *args)
      refute_predicate status, :success?
      assert_includes error, '--ref'
      refute_path_exists sentinel
    end
  end
end

class CliReviewWaiverTest < Minitest::Test
  # Option parsing rejects the flag before any GitHub client exists.
  def test_review_waiver_is_only_for_merge
    _output, error, status = Open3.capture3(CliTest::COMMAND, 'pr', 'owner/repo', '1', '--review-waiver', 'docs')

    refute_predicate status, :success?
    assert_match(/--review-waiver is only for merge/, error)
  end
end
