# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/pr_watch'
require 'shaka/pr_watch/command'
require 'open3'

module PrWatchFixtures
  HEAD = 'a' * 40
  MOVED = 'b' * 40

  private

  def check(name, state, bucket) = { 'name' => name, 'state' => state, 'bucket' => bucket }

  def frame(**values)
    defaults = { head: HEAD, state: 'OPEN', required: [check('validate', 'PENDING', 'pending')],
                 checks: [], comments: [], excluded: [] }
    current = defaults.merge(values)
    { pr: { 'headRefOid' => current[:head], 'state' => current[:state] }, required: current[:required],
      checks: current[:checks], comments: current[:comments], excluded: current[:excluded] }
  end

  def comments_packet(frame)
    { 'issue_comments' => frame[:comments].map { |id| { 'id' => id } },
      'review_summaries' => [], 'inline_comments' => [],
      'excluded_interactions' => frame[:excluded].map { |id| { 'id' => id } } }
  end
end

class PrWatchTest < Minitest::Test
  include PrWatchFixtures

  class FakeGitHub
    attr_reader :reads

    def initialize(frames)
      @frames = frames
      @reads = 0
    end

    def snapshot
      @reads += 1
      frame.fetch(:pr)
    end

    def required_checks
      raise Shaka::Error, 'checks unavailable' if frame.fetch(:required) == :unavailable

      frame.fetch(:required)
    end

    def configured_required_checks = []
    def checks = frame.fetch(:checks)
    def advance = @index = [(@index || 0) + 1, @frames.length - 1].min

    private

    def frame = @frames.fetch(@index || 0)
  end

  def test_wakes_when_required_and_review_checks_finish
    frames = [frame(required: [check('validate', 'PENDING', 'pending')],
                    checks: [check('claude-review', 'PENDING', 'pending')]),
              frame(required: [check('validate', 'SUCCESS', 'pass')],
                    checks: [check('claude-review', 'SUCCESS', 'pass')])]
    assert_equal 'checks_terminal', watch(frames)
  end

  def test_missing_review_job_waits_until_timeout
    frames = [frame(required: [check('validate', 'SUCCESS', 'pass')], checks: [])]
    assert_equal 'timeout', watch(frames, timeout: 2)
  end

  def test_no_configured_checks_waits_for_a_real_wake
    github = FakeGitHub.new([frame(required: [], checks: [])])
    now = 0
    adapters = { clock: -> { now }, sleeper: ->(seconds) { now += seconds },
                 comments: -> { comments_packet(frame) } }
    watcher = Shaka::PrWatch.new(github, head: HEAD, ci_jobs: [],
                                         settings: { interval: 1, settle: 1, timeout: 2 }, adapters:)
    assert_equal 'timeout', watcher.call
  end

  def test_failed_checks_are_terminal_and_wake_the_agent
    frames = [frame(required: [check('validate', 'FAILURE', 'fail')],
                    checks: [check('claude-review', 'FAILURE', 'fail')])]
    assert_equal 'checks_terminal', watch(frames)
  end

  def test_unavailable_required_checks_fail_instead_of_waiting
    error = assert_raises(Shaka::Error) { watch([frame(required: :unavailable)]) }

    assert_includes error.message, 'checks unavailable'
  end

  def test_head_move_wakes_before_check_completion
    frames = [frame, frame(head: MOVED)]
    assert_equal 'head_moved', watch(frames)
  end

  def test_new_trusted_comment_wakes_after_settle_window
    frames = [frame(comments: [1]), frame(comments: [1, 2]), frame(comments: [1, 2])]
    assert_equal 'trusted_comment', watch(frames)
  end

  def test_settle_window_wakes_before_the_next_regular_poll
    github = FakeGitHub.new([frame(required: [check('validate', 'SUCCESS', 'pass')])])
    now = 0
    adapters = { clock: -> { now }, sleeper: ->(seconds) { now += seconds },
                 comments: -> { comments_packet(frame) } }
    watcher = Shaka::PrWatch.new(github, head: HEAD, ci_jobs: [],
                                         settings: { interval: 60, settle: 15, timeout: 120 }, adapters:)
    assert_equal 'checks_terminal', watcher.call
    assert_equal 15, now
  end

  def test_saved_baseline_catches_a_comment_that_arrived_before_startup
    baseline = comments_packet(frame(comments: [1]))
    assert_equal 'trusted_comment', watch([frame(comments: [1, 2])], baseline:)
  end

  def test_timeout_preserves_a_known_comment_reason
    frames = [frame(comments: [1]), frame(comments: [1, 2])]
    assert_equal 'trusted_comment', watch(frames, timeout: 1)
  end

  def test_untrusted_comment_does_not_wake
    frames = [frame(comments: [1]), frame(comments: [1], excluded: [3])]
    assert_equal 'timeout', watch(frames, timeout: 2)
  end

  def test_previously_seen_comment_does_not_wake_when_it_reappears
    frames = [frame(comments: [1]), frame(comments: []), frame(comments: [1])]
    assert_equal 'timeout', watch(frames, timeout: 2)
  end

  def test_closed_pr_wakes
    frames = [frame, frame(state: 'MERGED')]
    assert_equal 'closed', watch(frames)
  end

  def test_cli_refuses_a_watch_without_a_trusted_ref
    command = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
    output, error, status = Open3.capture3(command, 'pr', 'watch', 'owner/repo', '42', '--head', HEAD)
    assert_equal '', error
    assert_equal "SHAKA_WAKE error: Expected OWNER/REPO NUMBER and --head SHA --ref SHA.\n", output
    refute_predicate status, :success?
  end

  private

  def watch(frames, timeout: 10, baseline: nil)
    github = FakeGitHub.new(frames)
    now = 0
    reader = -> { comments_packet(frames.fetch([now, frames.length - 1].min)) }
    tick = lambda do |seconds|
      now += seconds
      github.advance
    end
    settings = { interval: 1, timeout: timeout, settle: 1, baseline: }
    adapters = { clock: -> { now }, sleeper: tick, comments: reader }
    Shaka::PrWatch.new(github, head: HEAD, ci_jobs: ['claude-review'], settings:, adapters:).call
  end
end

class PrWatchTransitionsTest < Minitest::Test
  include PrWatchFixtures

  FakeGitHub = PrWatchTest::FakeGitHub

  def test_head_move_after_checks_read_wakes_before_comments
    github = Class.new(FakeGitHub) do
      def snapshot
        current = super
        reads == 4 ? current.merge('headRefOid' => 'b' * 40) : current
      end
    end.new([frame])
    adapters = { comments: -> { comments_packet(frame) }, sleeper: ->(_seconds) { flunk 'missed head move' } }
    watcher = Shaka::PrWatch.new(github, head: HEAD, ci_jobs: [], settings: {}, adapters:)
    assert_equal 'head_moved', watcher.call
  end

  def test_clock_crossing_deadline_before_sleep_wakes_normally
    times = [0, 0, 2, 2]
    sleeps = []
    adapters = { clock: -> { times.shift || 2 }, sleeper: ->(seconds) { sleeps << seconds },
                 comments: -> { comments_packet(frame) } }
    watcher = Shaka::PrWatch.new(FakeGitHub.new([frame]), head: HEAD, ci_jobs: [],
                                                          settings: { interval: 1, timeout: 1 }, adapters:)
    assert_equal 'timeout', watcher.call
    assert_equal [0], sleeps
  end

  def test_new_review_comment_wakes_when_its_id_matches_an_issue_comment
    github = FakeGitHub.new([frame])
    calls = 0
    reader = lambda do
      calls += 1
      packet = comments_packet(frame(comments: [1]))
      packet['review_summaries'] = [{ 'id' => 1 }] if calls > 1
      packet
    end
    assert_equal 'trusted_comment', watch_with(github, reader:, timeout: 3).first
  end

  def test_pending_checks_clear_a_terminal_wake_before_it_settles
    frames = %w[pass pending pending pass pass].map do |state|
      row = state == 'pass' ? check('validate', 'SUCCESS', 'pass') : check('validate', 'PENDING', 'pending')
      frame(required: [row])
    end
    reason, elapsed = watch_with(FakeGitHub.new(frames), reader: -> { comments_packet(frame) }, timeout: 8)
    assert_equal 'checks_terminal', reason
    assert_equal 4, elapsed
  end

  def test_one_review_wait_wakes_after_one_job_finishes
    github = FakeGitHub.new([review_frame])
    reason, = watch_with(github, reader: -> { comments_packet(frame) }, timeout: 3,
                                 ci_jobs: %w[first second], ci_wait: 'one')
    assert_equal 'checks_terminal', reason
  end

  def test_all_review_wait_keeps_waiting_for_second_job
    github = FakeGitHub.new([review_frame])
    reason, = watch_with(github, reader: -> { comments_packet(frame) }, timeout: 3,
                                 ci_jobs: %w[first second], ci_wait: 'all')
    assert_equal 'timeout', reason
  end

  def test_none_review_wait_ignores_pending_review_jobs
    github = FakeGitHub.new([review_frame])
    reason, = watch_with(github, reader: -> { comments_packet(frame) }, timeout: 3,
                                 ci_jobs: %w[first second], ci_wait: 'none')

    assert_equal 'checks_terminal', reason
  end

  def test_required_checks_wake_when_ci_review_is_omitted
    ready = frame(required: [check('validate', 'SUCCESS', 'pass')])
    reason, = watch_with(FakeGitHub.new([ready]), reader: -> { comments_packet(frame) },
                                                  timeout: 3, ci_jobs: [], ci_wait: 'one')

    assert_equal 'checks_terminal', reason
  end

  private

  def review_frame
    frame(required: [check('validate', 'SUCCESS', 'pass')],
          checks: [check('first', 'SUCCESS', 'pass'), check('second', 'PENDING', 'pending')])
  end

  def watch_with(github, reader:, timeout:, ci_jobs: [], ci_wait: 'one')
    now = 0
    sleeper = lambda do |seconds|
      now += seconds
      github.advance
    end
    adapters = { clock: -> { now }, sleeper:, comments: reader }
    settings = { interval: 1, settle: 1, timeout:, ci_review_wait: ci_wait }
    watcher = Shaka::PrWatch.new(github, head: HEAD, ci_jobs:, settings:, adapters:)
    [watcher.call, now]
  end
end

class PrWatchBaselineTest < Minitest::Test
  def test_command_uses_trusted_review_jobs_and_required_checks
    seam = Struct.new(:review, :merge).new({ 'ci_review_jobs' => ['claude-review'], 'ci_review_wait' => 'one' },
                                           { 'required_checks' => ['validate'] })
    options = { root: Dir.pwd, ref: 'a' * 40, head: 'b' * 40, ci_review_wait: 'all' }
    with_trusted_config(seam) do
      watcher = Shaka::PrWatch::Command.watcher(['owner/repo', '42'], options)
      settings = Shaka::PrWatch::Command.watch_settings(options, seam)

      assert_equal ['claude-review'], watcher.instance_variable_get(:@ci_jobs)
      assert_equal({ ci_review_wait: 'all', seam_required_checks: ['validate'] }, settings)
    end
  end

  def test_task_review_wait_cannot_lower_the_trusted_setting
    seam = Struct.new(:review, :merge).new({ 'ci_review_wait' => 'one' }, {})
    options, = Shaka::PrWatch::Command.parse(['--ci-review-wait', 'none'])

    assert_equal 'none', options[:ci_review_wait]
    assert_equal 'one', Shaka::PrWatch::Command.watch_settings(options, seam)[:ci_review_wait]
  end

  def test_omitted_ci_review_is_not_watched_for_a_trivial_task
    seam = Struct.new(:review, :merge).new({ 'required' => 'meaningful_changes',
                                             'ci_review_jobs' => ['claude-review'], 'ci_review_wait' => 'one' }, {})
    options, = Shaka::PrWatch::Command.parse(['--ci-review-not-required'])

    assert_empty Shaka::PrWatch::Command.review_jobs(options, seam)
    assert_equal 'one', Shaka::PrWatch::Command.watch_settings(options, seam)[:ci_review_wait]
  end

  def test_required_ci_review_cannot_be_omitted
    seam = Struct.new(:review, :merge).new({ 'required' => 'always', 'ci_review_jobs' => ['claude-review'] }, {})

    error = assert_raises(Shaka::Error) do
      Shaka::PrWatch::Command.review_jobs({ ci_review_not_required: true }, seam)
    end
    assert_includes error.message, 'review.required: meaningful_changes'
  end

  def test_accepts_a_saved_comments_packet_for_the_expected_head
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'comments.json')
      File.write(path, JSON.generate('head' => 'a' * 40, 'issue_comments' => [],
                                     'review_summaries' => [], 'inline_comments' => []))

      assert_equal 'a' * 40, Shaka::PrWatch::Command.baseline(baseline: path, head: 'a' * 40)['head']
    end
  end

  def test_malformed_comment_packet_fails_with_a_watcher_error
    github = PrWatchTest::FakeGitHub.new([{ pr: { 'headRefOid' => 'a' * 40, 'state' => 'OPEN' },
                                            required: [], checks: [] }])
    baseline = { 'issue_comments' => [1], 'review_summaries' => [], 'inline_comments' => [] }
    watcher = Shaka::PrWatch.new(github, head: 'a' * 40, ci_jobs: [], settings: { baseline: })

    error = assert_raises(Shaka::Error) { watcher.call }
    assert_equal 'Malformed comment packet.', error.message
  end

  def test_refuses_a_saved_comment_read_from_another_head
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'comments.json')
      File.write(path, JSON.generate('head' => 'b' * 40))

      error = assert_raises(Shaka::Error) do
        Shaka::PrWatch::Command.baseline(baseline: path, head: 'a' * 40)
      end
      assert_includes error.message, 'expected PR head'
    end
  end

  private

  def with_trusted_config(seam)
    source = Shaka::TrustedConfigSource
    original = source.method(:from_ref)
    source.define_singleton_method(:from_ref) { |**_args| seam }
    yield
  ensure
    source.define_singleton_method(:from_ref, original)
  end
end
