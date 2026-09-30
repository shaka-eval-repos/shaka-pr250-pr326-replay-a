# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'doctor_helper'

# A usage source counts only when this command can actually open it.
class DoctorUsageTest < Minitest::Test
  include DoctorHelper

  def test_a_missing_usage_source_degrades_without_blocking
    report, blocked = doctor(usage_files: [])
    assert_includes report, 'DEGRADED'
    refute blocked
  end

  # Cursor deliveries already published an all-UNKNOWN usage table; fail at doctor instead.
  def test_a_missing_cursor_stop_hook_source_blocks
    report, blocked = doctor(host: 'cursor', usage_files: [])
    assert_includes report, 'FAILED'
    assert_includes report, 'stop-hook'
    assert blocked
    assert_includes report, 'getting-started'
  end

  # Break: treating a missing this-chat jsonl as a missing hook fails every new Cursor chat
  # before stop has run, including when hooks.json already lists cursor-usage-hook.
  def test_a_missing_cursor_conversation_file_with_the_hook_installed_degrades
    report, blocked = doctor(host: 'cursor', usage_files: [], cursor_stop_hook: true)
    assert_includes report, 'DEGRADED'
    refute_includes report, 'FAILED'
    refute blocked
    assert_includes report, 'not readable yet'
  end

  def test_an_unreadable_cursor_stop_hook_source_blocks
    report, blocked = doctor(host: 'cursor', usage_files: ['/definitely/missing/transcript.jsonl'],
                             cursor_stop_hook: true)
    assert_includes report, 'FAILED'
    assert blocked
  end

  # Break: skipping hook? when a jsonl already exists reports HEALTHY after the hook is removed.
  def test_an_openable_cursor_file_still_fails_without_the_stop_hook
    report, blocked = doctor(host: 'cursor', usage_files: [__FILE__])
    assert_includes report, 'FAILED'
    assert blocked
  end

  # Break: a discover exception with the hook installed was reported as the expected first-stop miss.
  def test_a_cursor_discovery_error_with_the_hook_installed_blocks
    report, blocked = doctor(host: 'cursor', cursor_stop_hook: true,
                             usage_source: ->(_host) { raise Errno::EACCES, 'usage' })
    assert_includes report, 'FAILED'
    refute_includes report, 'not readable yet'
    assert blocked
  end

  def test_usage_source_check_keeps_object_inspect
    subject = Shaka::Doctor::UsageSourceCheck.new(host: 'cursor', system: stub_system(DEFAULTS))
    text = subject.inspect
    assert_kind_of String, text
    refute_match(/Usage source/, text)
  end

  # discover only locates sources, so a located-but-unreadable transcript is not healthy.
  def test_a_located_but_unreadable_usage_source_degrades
    report, blocked = doctor(usage_files: ['/definitely/missing/transcript.jsonl'])
    assert_includes report, 'DEGRADED'
    refute blocked
  end

  # An OpenCode session handle is not a file, so doctor cannot open it and must not claim it did.
  def test_a_session_handle_doctor_cannot_open_is_not_reported_as_ready
    report, blocked = doctor(usage_files: ['session:ses_example'])
    assert_includes report, 'DEGRADED'
    refute blocked
  end

  # Detection answers nil when several hosts are present, and a blank host is not a report.
  def test_an_ambiguous_host_is_named_rather_than_left_blank
    report, blocked = with_two_hosts { doctor(host: nil, usage_files: []) }
    assert_includes report, 'ambiguous'
    refute_match(/host +·/, report)
    refute blocked
  end

  # An empty transcript opens fine and still produces no usage rows.
  def test_an_empty_transcript_is_not_counted_as_a_usage_source
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'session.jsonl')
      File.write(path, '')
      report, blocked = doctor(usage_files: [path])
      assert_includes report, 'DEGRADED'
      refute blocked
    end
  end

  # A readable directory is not a transcript.
  def test_a_directory_is_not_counted_as_a_usage_source
    Dir.mktmpdir do |dir|
      report, blocked = doctor(usage_files: [dir])
      assert_includes report, 'DEGRADED'
      refute blocked
    end
  end

  private

  def with_two_hosts
    original = ENV.values_at('CODEX_THREAD_ID', 'CLAUDE_CODE_SESSION_ID')
    ENV['CODEX_THREAD_ID'] = 'thread'
    ENV['CLAUDE_CODE_SESSION_ID'] = 'session'
    yield
  ensure
    ENV['CODEX_THREAD_ID'], ENV['CLAUDE_CODE_SESSION_ID'] = original
  end
end
