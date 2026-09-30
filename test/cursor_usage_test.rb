# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'open3'
require 'shaka/usage/cursor_usage'

module CursorUsageFixture
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  HOOK = File.expand_path('../skills/shaka/scripts/cursor-usage-hook', __dir__)
  COMMIT = 'a' * 40
  SESSION = '11111111-1111-4111-8111-111111111111'
  OTHER = '22222222-2222-4222-8222-222222222222'
  OLD = '00000000-0000-4000-8000-000000000001'
  NEW = '00000000-0000-4000-8000-000000000002'
  THIRD = '00000000-0000-4000-8000-000000000003'
  CLEAR = { 'PI_CODING_AGENT' => nil, 'CODEX_THREAD_ID' => nil, 'CLAUDE_CODE_SESSION_ID' => nil,
            'CURSOR_CONVERSATION_ID' => nil }.freeze
  ROW = <<~ROW.chomp
    | Metric | cursor |
    | --- | --- |
    | Provider | cursor |
    | Configured model | grok-4.6 |
    | Routed model | cursor-grok-4.6-medium |
    | Effort | medium |
    | Input | 100 |
    | Cached input | 40 |
    | Output | 20 |
    | Reasoning output | UNKNOWN |
    | Cache writes | 7 |
    | Native total | UNKNOWN |
  ROW
  EMPTY_ROW = <<~ROW.chomp
    | Metric | cursor |
    | --- | --- |
    | Provider | cursor |
    | Configured model | UNKNOWN |
    | Routed model | UNKNOWN |
    | Effort | UNKNOWN |
    | Input | UNKNOWN |
    | Cached input | UNKNOWN |
    | Output | UNKNOWN |
    | Reasoning output | UNKNOWN |
    | Cache writes | UNKNOWN |
    | Native total | UNKNOWN |
  ROW
  CONTEXT_ROW = <<~ROW.chomp
    | Metric | cursor |
    | --- | --- |
    | Provider | cursor |
    | Configured model | grok-4.6 |
    | Routed model | cursor-grok-4.6-medium |
    | Effort | medium |
    | Input | UNKNOWN |
    | Cached input | UNKNOWN |
    | Output | UNKNOWN |
    | Reasoning output | UNKNOWN |
    | Cache writes | UNKNOWN |
    | Native total | UNKNOWN |
  ROW

  private

  def payload(generation, input, event: 'stop', conversation: SESSION)
    { conversation_id: conversation, generation_id: generation, model: 'cursor-grok-4.6-medium',
      model_id: 'grok-4.6', model_params: [{ id: 'effort', value: 'medium' }, { id: 'fast', value: 'false' }],
      hook_event_name: event, cursor_version: '3.20.21', input_tokens: input, output_tokens: 20,
      cache_read_tokens: 40, cache_write_tokens: 7, text: 'SENSITIVE-OUTPUT',
      user_email: 'SENSITIVE@example.com', transcript_path: '/private/SENSITIVE.jsonl' }
  end

  def grok47_record
    params = [{ id: 'context', value: '256k' }, { id: 'reasoning_effort', value: 'high' },
              { id: 'fast', value: 'false' }]
    stored(NEW, 100).merge(model: 'grok-4.7-high', model_id: 'grok-4.7', model_params: params)
  end

  def cursor_file_report(record)
    Dir.mktmpdir { |directory| report('--host', 'cursor', '--file', write_records(directory, [record])) }
  end

  def stored(generation, input, event: 'stop', timestamp: '2026-09-16T12:00:00Z')
    payload(generation, input, event: event).except(:text, :user_email, :transcript_path).merge(timestamp: timestamp)
  end

  def write_records(directory, records, name: "#{SESSION}.jsonl")
    path = File.join(directory, name)
    File.write(path, "#{records.map { |record| JSON.generate(record) }.join("\n")}\n")
    path
  end

  def report(*, environment: {})
    output, error, status = Open3.capture3(CLEAR.merge(environment), COMMAND, 'usage', '--commit', COMMIT,
                                           '--contribution', 'implementation', *)
    assert_predicate status, :success?, error
    output
  end

  def empty_cursor_report(directory, extra = {})
    report(environment: empty_cursor_env(directory).merge(extra))
  end

  def empty_cursor_env(directory)
    { 'CURSOR_CONVERSATION_ID' => SESSION, 'CURSOR_USAGE_DIR' => directory }
  end

  def assert_cursor_unavailable(output, row)
    assert_includes output, 'Responses: UNKNOWN'
    assert_includes output, Shaka::CursorUsage::UNAVAILABLE
    assert_includes output, row
    refute_includes output, '| 0 |'
  end

  def latest_and_duplicate(directory)
    write_records(directory, [stored(OLD, 900, timestamp: '2026-09-16T11:00:00Z'),
                              stored(NEW, 100), stored(NEW, 100, event: 'afterAgentResponse')])
  end
end

class CursorUsageTest < Minitest::Test
  include CursorUsageFixture

  def test_counts_each_generation_once_from_the_latest_turn
    Dir.mktmpdir do |directory|
      output = report('--host', 'cursor', '--file', latest_and_duplicate(directory))
      assert_includes output, ROW
      assert_metric output, 'USD estimate', '$0.000260'
      assert_includes output, '1 responses'
      assert_includes output, 'Cursor source versions: 3.20.21'
      assert_includes output.split('<details>').first, 'latest generation only'
      refute_match(/900|SENSITIVE/, without_usage_identity(output))
    end
  end

  def test_discovers_the_conversation_file
    Dir.mktmpdir do |directory|
      write_records(directory, [stored(OLD, 900), stored(NEW, 100)])
      env = { 'CURSOR_CONVERSATION_ID' => SESSION, 'CURSOR_USAGE_DIR' => directory }
      discovered = report(environment: env)
      assert_metric discovered, 'Input', 100
      assert_metric discovered, 'Cached input', 40
      assert_metric discovered, 'Cache writes', 7
      refute_includes discovered, SESSION
    end
  end

  def test_selects_all_or_explicit_turns
    Dir.mktmpdir do |directory|
      file = write_records(directory, [stored(OLD, 900), stored(NEW, 100)])
      assert_includes report('--host', 'cursor', '--file', file, '--all-turns'), '| 1000 |'
      assert_includes report('--host', 'cursor', '--file', file, '--turn', OLD), '| 900 |'
    end
  end

  def test_each_file_contributes_its_latest_generation
    Dir.mktmpdir do |directory|
      first = write_records(directory, [stored(OLD, 900), stored(NEW, 100)])
      second = write_records(directory, [stored(THIRD, 200)], name: "#{OTHER}.jsonl")
      output = report('--host', 'cursor', '--file', first, '--file', second)
      assert_metric output, 'Input', 300
      assert_metric output, 'Cached input', 80
      assert_metric output, 'Cache writes', 14
      refute_includes output, '| 900 |'
    end
  end

  def test_hook_omits_private_hook_fields
    Dir.mktmpdir do |directory|
      env = CLEAR.merge('CURSOR_USAGE_DIR' => directory)
      _out, err, status = Open3.capture3(env, HOOK, stdin_data: JSON.generate(payload(NEW, 100)))
      assert_predicate status, :success?, err
      saved = File.read(File.join(directory, "#{SESSION}.jsonl"))
      refute_match(/SENSITIVE/, saved)
      assert_equal NEW, JSON.parse(saved.lines.first)['generation_id']
    end
  end

  def test_grok_47_reasoning_effort_is_priced_without_a_context_surcharge
    output = cursor_file_report(grok47_record)
    assert_includes output, '| Configured model | grok-4.7 |'
    assert_includes output, '| Routed model | grok-4.7-high |'
    assert_includes output, '| Effort | high |'
    assert_includes output, '| USD estimate | $0.000260 |'
    refute_includes output, '256K context threshold'
  end

  def test_named_effort_wins_over_reasoning_effort
    params = [{ id: 'effort', value: 'medium' }, { id: 'reasoning_effort', value: 'high' },
              { id: 'fast', value: 'false' }]
    output = cursor_file_report(stored(NEW, 100).merge(model_params: params))
    assert_includes output, '| Effort | medium |'
  end

  def test_hook_records_are_readable_by_the_usage_command
    Dir.mktmpdir do |directory|
      env = CLEAR.merge('CURSOR_USAGE_DIR' => directory)
      Open3.capture3(env, HOOK, stdin_data: JSON.generate(payload(NEW, 100)))
      output = report('--host', 'cursor', '--file', File.join(directory, "#{SESSION}.jsonl"))
      assert_includes output, ROW
      refute_includes output, 'SENSITIVE'
    end
  end
end

class CursorUsageFailuresTest < Minitest::Test
  include CursorUsageFixture

  def test_missing_token_fields_stay_unknown_without_zero_inflation
    Dir.mktmpdir do |directory|
      incomplete = stored(NEW, 100)
      incomplete.delete(:cache_read_tokens)
      file = write_records(directory, [payload('33333333-3333-4333-8333-333333333333', 9900, event: 'preToolUse'),
                                       incomplete])
      output = report('--host', 'cursor', '--file', file)
      assert_metric output, 'Cached input', 'UNKNOWN'
      refute_includes without_usage_identity(output), '9900'
    end
  end

  def test_discovery_ignores_another_conversation
    Dir.mktmpdir do |directory|
      write_records(directory, [stored(NEW, 100)], name: "#{OTHER}.jsonl")
      assert_cursor_unavailable(empty_cursor_report(directory), EMPTY_ROW)
    end
  end

  def test_host_context_fills_models_when_stop_records_are_missing
    Dir.mktmpdir do |directory|
      extra = { 'CURSOR_MODEL_ID' => 'grok-4.6', 'CURSOR_MODEL' => 'cursor-grok-4.6-medium',
                'CURSOR_MODEL_EFFORT' => 'medium' }
      output = empty_cursor_report(directory, extra)
      assert_cursor_unavailable(output, CONTEXT_ROW)
      refute_includes output, '| 100 |'
    end
  end

  def test_explicit_files_do_not_copy_ambient_cursor_models
    Dir.mktmpdir do |directory|
      file = File.join(directory, 'empty.jsonl')
      File.write(file, '')
      env = { 'CURSOR_MODEL_ID' => 'grok-4.6', 'CURSOR_MODEL' => 'cursor-grok-4.6-medium',
              'CURSOR_MODEL_EFFORT' => 'medium' }
      output = report('--host', 'cursor', '--file', file, environment: env)
      assert_includes output, 'usage reader unavailable'
      refute_includes output, 'grok-4.6'
    end
  end

  # Cursor selects generations in its own reader, so it needs its own unmatched-turn check.
  def test_turn_that_matches_no_generation_fails_and_names_the_expected_field
    Dir.mktmpdir do |directory|
      file = write_records(directory, [stored(NEW, 100)])
      output, error, status = Open3.capture3(CLEAR, COMMAND, 'usage', '--host', 'cursor', '--file', file,
                                             '--commit', COMMIT, '--contribution', 'implementation',
                                             '--turn', 'typo')
      refute_predicate status, :success?
      assert_empty output
      assert_match(/typo.*generation_id/, error)
    end
  end

  def test_explicit_turns_do_not_copy_ambient_cursor_models
    Dir.mktmpdir do |directory|
      env = { 'CURSOR_MODEL_ID' => 'grok-4.6' }
      output = report('--turn', NEW, environment: empty_cursor_env(directory).merge(env))
      assert_includes output, 'usage reader unavailable'
      refute_includes output, 'grok-4.6'
    end
  end

  def test_unreadable_lines_are_disclosed_without_dropping_valid_rows
    Dir.mktmpdir do |directory|
      file = write_records(directory, [stored(NEW, 100)])
      File.write(file, "{broken\n#{File.read(file)}")
      output = report('--host', 'cursor', '--file', file)
      assert_includes output, '| 100 |'
      assert_includes output, 'Unreadable or unidentifiable records'
    end
  end

  def test_missing_generation_id_is_disclosed_to_time_scoped_reports
    Dir.mktmpdir do |directory|
      file = write_records(directory, [stored(NEW, 100), stored(nil, 900)])
      reader = Shaka::CursorUsage.new([file], [], all_turns: true)

      assert_includes reader.gaps, 'Unreadable or unidentifiable records'
    end
  end

  def test_hook_ignores_non_stop_payloads_and_empty_stdin
    Dir.mktmpdir do |directory|
      env = CLEAR.merge('CURSOR_USAGE_DIR' => directory)
      Open3.capture3(env, HOOK, stdin_data: JSON.generate(payload(NEW, 1, event: 'preToolUse')))
      Open3.capture3(env, HOOK, stdin_data: '')
      refute_path_exists File.join(directory, "#{SESSION}.jsonl")
    end
  end
end
