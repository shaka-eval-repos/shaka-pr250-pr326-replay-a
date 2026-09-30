# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'yaml'

class ReviewWorkflowTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('review-result')
    @summary = File.join(@directory, 'summary.md')
    @execution = File.join(@directory, 'execution.json')
    workflow = YAML.load_file(File.expand_path('../.github/workflows/claude-code-review.yml', __dir__))
    steps = workflow.dig('jobs', 'claude-review', 'steps')
    @script = steps.find { |step| step.dig('env', 'EXECUTION_FILE') }.fetch('run')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_missing_execution_is_prominently_unavailable_not_completed
    output, _status, summary = run_result

    assert_includes output, '::warning::'
    assert_includes summary, 'UNAVAILABLE'
    refute_includes summary, 'COMPLETED'
  end

  def test_failed_action_is_visible_even_without_execution
    _output, status, summary = run_result(outcome: 'failure')

    refute_predicate status, :success?
    assert_includes summary, 'UNAVAILABLE'
  end

  def test_missing_malformed_and_failed_results_cannot_report_completed
    [[], '{broken', [{ type: 'result' }], [result.merge(is_error: true)],
     [result.merge(subtype: 'error_max_turns')], [result.merge(num_turns: 0)]].each do |data|
      _output, status, summary = run_result(data)
      refute_predicate status, :success?, data.inspect
      assert_includes summary, 'UNAVAILABLE'
      refute_includes summary, 'COMPLETED'
    end
  end

  def test_successful_execution_stays_unverified_without_a_visible_review
    [[result], "#{JSON.generate(type: 'assistant')}\n#{JSON.generate(result)}\n"].each do |data|
      output, status, summary = run_result(data)
      assert_predicate status, :success?, output
      assert_includes summary, 'UNVERIFIED'
      refute_includes summary, 'COMPLETED'
      assert_includes summary, 'a' * 40
      refute_includes summary, 'UNAVAILABLE'
    end
  end

  private

  def result
    { type: 'result', subtype: 'success', is_error: false, num_turns: 2 }
  end

  def run_result(data = nil, outcome: 'success')
    File.write(@execution, data.is_a?(String) ? data : JSON.generate(data)) unless data.nil?
    File.write(@summary, '')
    environment = { 'EXECUTION_FILE' => data.nil? ? '' : @execution, 'REVIEW_OUTCOME' => outcome,
                    'REVIEW_HEAD' => 'a' * 40, 'GITHUB_STEP_SUMMARY' => @summary }
    output, status = Open3.capture2e(environment, 'bash', '-c', @script)
    [output, status, File.read(@summary)]
  end
end
