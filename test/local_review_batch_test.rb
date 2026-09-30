# frozen_string_literal: true

require_relative 'local_review_test'
require 'shaka/local_review/ledger'
require 'shaka/local_review/comment'

class LocalReviewBatchTest < Minitest::Test
  COMMAND = LocalReviewCodexTest::COMMAND
  include LocalReviewFixture
  include LocalReviewLoopSteps

  def teardown
    Array(@results).each { |result| cleanup_artifacts(result) }
  end

  def test_same_head_peers_are_isolated_and_all_dispositions_block_next_head
    in_loop do |head|
      loop_round(head, findings: 1)
      assert_isolated_peer(head)
      fix = fix_commit
      record_number(2, finding('peer'))
      assert_refused(fix, 'Record round 1')
      record_number(1, finding('first'))
      loop_round(fix, findings: 0)
      assert_batch_evidence
    end
  end

  def test_concurrent_fake_processes_preserve_peer_completions
    in_loop do |head|
      gate, workers = start_concurrent_reviewers(head)
      wait_for_pending(2)
      assert_pending_guards(head)
      File.write(gate, 'go')
      assert_concurrent_completion(workers, head)
    ensure
      File.write(gate, 'go') if gate
      workers&.each(&:join)
    end
  end

  def test_moved_checkout_rejects_both_concurrent_reports
    in_loop do |head|
      gate, workers = start_concurrent_reviewers(head)
      wait_for_pending(2)
      fix_commit
      File.write(gate, 'go')
      assert_stale_completions(workers)
    ensure
      File.write(gate, 'go') if gate
      workers&.each(&:join)
    end
  end

  def test_stale_record_cannot_replace_a_peer_disposition
    in_loop do |head|
      loop_round(head, findings: 1)
      stale = Shaka::LocalReviewLedger.new(@ledger)
      stale.rounds
      record_number(1, finding('valid'))
      error = assert_raises(Shaka::Error) { stale.record!({ 'findings' => finding('stale') }, number: 1) }
      assert_includes error.message, 'Stale ledger'
      assert_equal 'valid', JSON.parse(File.read(@ledger)).dig('rounds', 0, 'findings', 0, 'summary')
    end
  end

  def test_previous_batch_fixes_from_every_reviewer_must_be_in_history
    in_loop do |head|
      loop_round(head, findings: 0)
      claude_round(head, findings: 1)
      side = record_side_fix
      commit!(@root, 'unrelated', 'Other fix')
      assert_refused(git!(@root, 'rev-parse', 'HEAD').strip, "does not build on #{side}")
    end
  end
end

# Shared setup for fake CLI reviewers in concurrent batch tests.
module LocalReviewBatchFixture
  private

  def assert_stale_completions(workers)
    workers.each do |worker|
      output, _error, status = worker.value
      refute_predicate status, :success?
      assert_includes JSON.parse(output).fetch('reason'), 'Checkout HEAD is'
    end
    data = JSON.parse(File.read(@ledger))
    assert_empty data.fetch('rounds')
    assert_empty data.fetch('pending')
  end

  def assert_isolated_peer(head)
    peer = claude_round(head, findings: 1)
    assert_equal 2, peer.fetch('round')
    refute_includes File.read(@trace), 'PRIOR ROUNDS'
  end

  def assert_pending_guards(head)
    ledger = Shaka::LocalReviewLedger.new(@ledger)
    assert_raises(Shaka::Error) { ledger.check_next!(base: @base, head: 'f' * 40, reviewer: 'xai/grok') }
    assert_raises(Shaka::Error) { ledger.check_next!(base: @base, head:, reviewer: 'openai/codex') }
  end

  def record_side_fix
    git!(@root, 'checkout', '--quiet', '-b', 'side')
    side = fix_commit
    record_number(2, [{ 'id' => 'F1', 'summary' => 'Peer defect', 'class' => 'defect',
                        'disposition' => 'fixed', 'commit' => side }])
    git!(@root, 'checkout', '--quiet', '-')
    side
  end

  def assert_batch_evidence
    prompt = File.read(@trace)
    assert_includes prompt, 'first'
    assert_includes prompt, 'peer'
    body = Shaka::LocalReviewComment.render(JSON.parse(File.read(@ledger)))
    assert_equal 3, body.scan('<details>').size
    assert_includes body, 'anthropic/claude'
    assert_includes body, 'first'
    assert_includes body, 'peer'
  end

  def start_concurrent_reviewers(head)
    gate = File.join(File.dirname(@ledger), 'release')
    fake_codex(@bin, head)
    fake_claude(@bin, head)
    delay_reviewers(gate)
    [gate, %w[openai/codex anthropic/claude].map { |id| concurrent_worker(id, head) }]
  end

  def delay_reviewers(gate)
    %w[codex claude].each do |name|
      path = File.join(@bin, name)
      script = File.read(path).sub("require 'json'", "require 'json'\nsleep 0.01 until File.exist?(#{gate.inspect})")
      File.write(path, script)
    end
  end

  def concurrent_worker(id, head)
    Thread.new do
      run_review(@root, @base, head, @bin, reviewer: id, ledger: @ledger,
                                           env: { 'REVIEW_TRACE' => "#{@trace}-#{id.split('/').first}" })
    end
  end

  def assert_concurrent_completion(workers, head)
    @results = workers.map.with_index do |worker, index|
      output, error, status = worker.value
      assert_successful_review(output, error, status, head, %w[openai/codex anthropic/claude][index])
    end
    assert_peer_rows
    assert_empty JSON.parse(File.read(@ledger)).fetch('pending')
  end

  def assert_peer_rows
    data = JSON.parse(File.read(@ledger))
    reviewers = data.fetch('rounds').map { |round| round['reviewer'] }.sort
    assert_equal %w[anthropic/claude openai/codex], reviewers
    assert_equal [1, 2], @results.map { |result| result['round'] }.sort
    assert_equal 2, Shaka::LocalReviewComment.render(data).scan('<details>').size
  end

  def claude_round(head, findings:)
    fake_claude(@bin, head)
    path = File.join(@bin, 'claude')
    File.write(path, File.read(path).sub('FINDINGS 0', "FINDINGS #{findings}"))
    output, error, status = run_review(@root, @base, head, @bin, reviewer: 'anthropic/claude', ledger: @ledger,
                                                                 env: { 'REVIEW_TRACE' => @trace })
    result = assert_successful_review(output, error, status, head, 'anthropic/claude')
    (@results ||= []) << result
    result
  end

  def finding(summary)
    [{ 'id' => 'F1', 'summary' => summary, 'class' => 'risk', 'disposition' => 'documented' }]
  end

  def record_number(number, findings)
    ledger = Shaka::LocalReviewLedger.new(@ledger)
    ledger.record!({ 'findings' => findings }, number:)
  end

  def wait_for_pending(count)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      break if File.exist?(@ledger) && JSON.parse(File.read(@ledger)).fetch('pending', []).size == count
      raise 'Fake reviewers did not start' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end

LocalReviewBatchTest.include(LocalReviewBatchFixture)
