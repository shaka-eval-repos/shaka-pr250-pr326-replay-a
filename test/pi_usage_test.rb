# frozen_string_literal: true

require_relative 'test_helper'
require 'json'

module PiUsageFixture
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  COMMIT = 'a' * 40
  SESSION = '00000000-0000-4000-8000-000000000003'
  CLEAR = { 'PI_CODING_AGENT' => nil, 'PI_SESSION_ID' => nil, 'PI_SESSION_FILE' => nil,
            'CODEX_THREAD_ID' => nil, 'CLAUDE_CODE_SESSION_ID' => nil,
            'CURSOR_CONVERSATION_ID' => nil, 'OPENCODE_SESSION_ID' => nil }.freeze
  OLD_TURN = '33333333'
  ABANDONED_TURN = '55555555'
  CURRENT_TURN = '99999999'
  OLD_ROUTE = %w[observed-old configured-old routed-old].freeze
  ABANDONED_ROUTE = %w[observed-abandoned configured-abandoned routed-abandoned].freeze
  CURRENT_ROUTE = %w[observed-new configured-new routed-new].freeze
  REDACTED_OUTPUT = /800|900|SENSITIVE|response-|private-call|#{Regexp.escape(SESSION)}/

  private

  def header(identity = SESSION, version: 3)
    { type: 'session', version: version, id: identity, timestamp: '2026-09-17T08:00:00.000Z',
      cwd: '/private/SENSITIVE-PATH' }
  end

  def entry(type, id, parent, **fields)
    { type: type, id: id, parentId: parent, timestamp: '2026-09-17T08:00:00.000Z', **fields }
  end

  def user(id, parent)
    entry('message', id, parent,
          message: { role: 'user', content: 'SENSITIVE-PROMPT', timestamp: 1_789_632_000_000 })
  end

  def assistant(id, parent, response, input, route)
    entry('message', id, parent,
          message: { role: 'assistant', responseId: response, provider: route[0], model: route[1],
                     responseModel: route[2], content: [{ type: 'text', text: 'SENSITIVE-RESPONSE' }],
                     timestamp: 1_789_632_000_000,
                     usage: { input: input, output: 20, cacheRead: 40, cacheWrite: 7,
                              reasoning: 5, totalTokens: input + 67,
                              cost: { total: input / 1_000_000.0 } } })
  end

  def branched_session
    [header, *old_branch, *abandoned_branch, *current_branch]
  end

  def old_branch
    [entry('model_change', '11111111', nil, provider: 'selected-old', modelId: 'configured-old'),
     entry('thinking_level_change', '22222222', '11111111', thinkingLevel: 'high'),
     user(OLD_TURN, '22222222'), assistant('44444444', OLD_TURN, 'response-old', 900, OLD_ROUTE)]
  end

  def abandoned_branch
    [user(ABANDONED_TURN, '44444444'),
     assistant('66666666', ABANDONED_TURN, 'response-abandoned', 800, ABANDONED_ROUTE)]
  end

  def current_branch
    [entry('model_change', '77777777', '44444444', provider: 'selected-new', modelId: 'configured-new'),
     entry('thinking_level_change', '88888888', '77777777', thinkingLevel: 'low'), user(CURRENT_TURN, '88888888'),
     assistant('aaaaaaaa', CURRENT_TURN, 'response-current-1', 100, CURRENT_ROUTE), tool_result,
     assistant('cccccccc', 'bbbbbbbb', 'response-current-2', 200, CURRENT_ROUTE)]
  end

  def tool_result
    entry('message', 'bbbbbbbb', 'aaaaaaaa',
          message: { role: 'toolResult', toolCallId: 'private-call', toolName: 'bash',
                     content: [{ type: 'text', text: 'SENSITIVE-TOOL-OUTPUT' }], isError: false,
                     timestamp: 1_789_632_000_000 })
  end

  def write_session(directory, records, name: 'session.jsonl', raw_tail: '')
    file = File.join(directory, name)
    File.write(file, "#{records.map { |record| JSON.generate(record) }.join("\n")}\n#{raw_tail}")
    file
  end

  def capture_report(*, environment: {})
    Open3.capture3(CLEAR.merge(environment), COMMAND, 'usage', '--commit', COMMIT,
                   '--contribution', 'implementation', *)
  end

  def report(*, environment: {})
    output, error, status = capture_report(*, environment: environment)
    assert_predicate status, :success?, error
    output
  end

  def discovered(file, identity: SESSION, extra: {})
    report(environment: { 'PI_CODING_AGENT' => 'true', 'PI_SESSION_ID' => identity,
                          'PI_SESSION_FILE' => file, **extra })
  end

  def assert_active_rows(output)
    assert_metric output, 'Input', 900, 300
    assert_metric output, 'Native total', 967, 434
    assert_includes output, '3 responses'
    refute_match(/800|abandoned/, without_usage_identity(output))
  end

  def assert_current_row(output)
    assert_metric output, 'Provider', 'observed-new'
    assert_metric output, 'Input', 300
    assert_metric output, 'Native total', 434
  end

  def assert_pi_cost(output, *amounts)
    assert_metric output, 'USD estimate', *amounts
    refute_includes output, 'Credits estimate'
    refute_includes output, 'cursor.com'
    refute_includes output, '2026-09-16'
  end

  def assert_unavailable(file)
    output = report('--host', 'pi', '--file', file, '--all-turns')
    assert_includes output, 'Responses: UNKNOWN'
    assert_includes output, 'Unreadable or unidentifiable records'
    refute_match(/999|SENSITIVE|deadbeef/, without_usage_identity(output))
  end
end

module PiUsageMutationFixture
  private

  def forked_records(without_response_ids)
    original = Marshal.load(Marshal.dump(branched_session))
    forked = Marshal.load(Marshal.dump(branched_session))
    forked[0] = header('forked-session')
    [original, forked].each { |records| remove_response_ids(records) } if without_response_ids
    [original, forked]
  end

  def fork_report(directory, without_response_ids)
    original, forked = forked_records(without_response_ids)
    first = write_session(directory, original, name: 'first.jsonl')
    second = write_session(directory, forked, name: 'forked.jsonl')
    report('--host', 'pi', '--file', first, '--file', second, '--all-turns')
  end

  def remove_response_ids(records)
    records.each { |record| record[:message]&.delete(:responseId) }
  end

  def current_messages(records)
    records.filter_map { |record| record[:message] }
           .select { |message| message[:model] == 'configured-new' }
  end

  def remove_optional_evidence(records)
    messages = current_messages(records)
    messages.each { |message| message.delete(:responseModel) }
    messages.first[:usage].delete(:reasoning)
    messages.last[:usage][:reasoning] = nil
  end

  def set_native_cost(records, cost)
    usage = records.last[:message][:usage]
    cost.nil? ? usage.delete(:cost) : usage[:cost] = { total: cost }
  end
end

class PiUsageTest < Minitest::Test
  include PiUsageFixture
  include PiUsageMutationFixture

  def test_detects_pi_and_uses_latest_active_branch_turn
    Dir.mktmpdir do |directory|
      output = discovered(write_session(directory, branched_session))
      assert_current_row(output)
      assert_pi_cost output, '$0.000300'
      assert_includes output, 'Pi recorded native nominal USD'
      assert_includes output, '2 responses'
      assert_includes output, 'Pi source versions: 3'
      assert_includes output, 'latest user turn on the active branch'
      refute_match(REDACTED_OUTPUT, without_usage_identity(output))
    end
  end

  def test_mixed_host_context_requires_an_explicit_host
    Dir.mktmpdir do |directory|
      file = write_session(directory, branched_session)
      environment = CLEAR.merge('PI_CODING_AGENT' => 'true', 'PI_SESSION_ID' => SESSION,
                                'PI_SESSION_FILE' => file, 'CODEX_THREAD_ID' => 'nested-codex')
      output, error, status = capture_report(environment: environment)
      refute_predicate status, :success?
      assert_empty output
      assert_includes error, 'invalid options'
      assert_current_row(report('--host', 'pi', environment: environment))
    end
  end

  def test_explicit_and_all_turns_never_include_abandoned_branches
    Dir.mktmpdir do |directory|
      file = write_session(directory, branched_session)
      explicit = report('--host', 'pi', '--file', file, '--turn', OLD_TURN, '--turn', CURRENT_TURN)
      all = report('--host', 'pi', '--file', file, '--all-turns')
      [explicit, all].each { |output| assert_active_rows(output) }
    end
  end

  def test_forked_sessions_deduplicate_response_ids_and_entry_fallbacks
    [false, true].each do |remove_response_ids|
      Dir.mktmpdir do |directory|
        output = fork_report(directory, remove_response_ids)
        assert_includes output, '3 responses'
        assert_metric output, 'Input', 900, 300
        assert_metric output, 'Native total', 967, 434
        assert_pi_cost output, '$0.000900', '$0.000300'
      end
    end
  end

  def test_missing_response_model_and_reasoning_remain_unknown
    Dir.mktmpdir do |directory|
      records = Marshal.load(Marshal.dump(branched_session))
      remove_optional_evidence(records)
      output = report('--host', 'pi', '--file', write_session(directory, records))
      assert_metric output, 'Routed model', 'UNKNOWN'
      assert_metric output, 'Input', 300
      assert_metric output, 'Reasoning output', 'UNKNOWN'
      assert_metric output, 'Native total', 434
    end
  end

  def test_zero_output_proves_zero_reasoning_when_counter_is_omitted
    Dir.mktmpdir do |directory|
      records = Marshal.load(Marshal.dump(branched_session))
      message = records.last[:message]
      message[:stopReason] = 'aborted'
      message[:usage].merge!(output: 0, totalTokens: 247)
      message[:usage].delete(:reasoning)
      output = report('--host', 'pi', '--file', write_session(directory, records))
      assert_metric output, 'Native total', 414
    end
  end

  def test_compaction_usage_is_disclosed_but_not_counted
    Dir.mktmpdir do |directory|
      records = branched_session << entry('compaction', 'dddddddd', 'cccccccc',
                                          summary: 'SENSITIVE-SUMMARY',
                                          usage: { input: 999, output: 99, cacheRead: 0, cacheWrite: 0,
                                                   totalTokens: 1098 })
      output = report('--host', 'pi', '--file', write_session(directory, records))
      assert_includes output, '2 responses'
      assert_includes output, 'Compaction/summary usage on active branch excluded'
      refute_match(/1098|SENSITIVE/, without_usage_identity(output))
    end
  end
end

class PiInvalidReasoningCostTest < Minitest::Test
  include PiUsageFixture

  def test_invalid_reasoning_on_openai_pi_does_not_restore_rate_cards
    Dir.mktmpdir do |directory|
      output = report('--host', 'pi', '--file', write_session(directory, openai_terra_invalid_reasoning))
      assert_pi_cost output, '$0.000100', 'UNKNOWN'
      refute_includes output, 'learn.chatgpt.com'
      refute_includes output, 'developers.openai.com'
    end
  end

  def test_missing_usage_on_openai_pi_does_not_restore_rate_cards
    Dir.mktmpdir do |directory|
      records = openai_terra_invalid_reasoning
      records.last[:message].delete(:usage)
      output = report('--host', 'pi', '--file', write_session(directory, records))
      assert_pi_cost output, '$0.000100', 'UNKNOWN'
      refute_includes output, 'learn.chatgpt.com'
      refute_includes output, 'developers.openai.com'
    end
  end

  private

  def openai_terra_invalid_reasoning
    records = Marshal.load(Marshal.dump(branched_session))
    message = records.last[:message]
    message[:provider] = 'openai'
    message[:model] = 'gpt-5.6-terra'
    message[:usage][:reasoning] = 21
    records
  end
end

class PiUsageFailuresTest < Minitest::Test
  include PiUsageFixture
  include PiUsageMutationFixture

  def test_ephemeral_pi_evidence_does_not_fall_back_to_codex
    assert_unknown_pi(report(environment: { 'PI_CODING_AGENT' => 'true' }))
  end

  def test_custom_session_identity_matches_exactly
    Dir.mktmpdir do |directory|
      records = branched_session
      records[0] = header('sdk.custom-session')
      output = discovered(write_session(directory, records), identity: 'sdk.custom-session')
      assert_current_row(output)
      assert_unknown_pi(discovered(write_session(directory, records), identity: 'other-session'))
    end
  end

  def test_only_v3_sessions_are_available
    Dir.mktmpdir do |directory|
      records = branched_session
      records[0] = header(SESSION, version: 2)
      assert_unavailable(write_session(directory, records))
    end
  end

  def test_missing_parent_makes_the_tree_unavailable
    Dir.mktmpdir do |directory|
      records = branched_session
      records.last[:parentId] = 'deadbeef'
      assert_unavailable(write_session(directory, records))
    end
  end

  def test_duplicate_entry_identity_makes_the_tree_unavailable
    Dir.mktmpdir do |directory|
      records = branched_session
      records << assistant('aaaaaaaa', CURRENT_TURN, 'SENSITIVE-CONFLICT', 999, CURRENT_ROUTE)
      assert_unavailable(write_session(directory, records))
    end
  end

  def test_malformed_json_makes_the_tree_unavailable
    Dir.mktmpdir do |directory|
      file = write_session(directory, branched_session, raw_tail: '{"SENSITIVE-INCOMPLETE"')
      assert_unavailable(file)
    end
  end

  def test_conflicting_response_copies_across_fork_headers_are_unknown
    Dir.mktmpdir do |directory|
      original, changed = forked_records(false)
      changed.last[:message][:usage].merge!(input: 999, totalTokens: 1066, cost: { total: 0.000999 })
      first = write_session(directory, original, name: 'first.jsonl')
      second = write_session(directory, changed, name: 'forked.jsonl')
      output = report('--host', 'pi', '--file', first, '--file', second)
      assert_includes output, 'Conflicting response copies'
      assert_metric output, 'Input', 100, 'UNKNOWN'
      assert_metric output, 'USD estimate', '$0.000100', 'UNKNOWN'
    end
  end

  def test_invalid_reasoning_makes_the_response_usage_unknown
    ['SENSITIVE', -1, 21].each do |reasoning|
      Dir.mktmpdir do |directory|
        records = Marshal.load(Marshal.dump(branched_session))
        records.last[:message][:usage][:reasoning] = reasoning
        output = report('--host', 'pi', '--file', write_session(directory, records))
        assert_metric output, 'Input', 'UNKNOWN'
        assert_includes output, 'Unreadable or unidentifiable records'
        refute_includes output, 'SENSITIVE'
      end
    end
  end

  def test_missing_or_invalid_native_cost_is_left_out_of_a_partial_estimate_without_losing_tokens
    [nil, 'SENSITIVE', -1].each do |cost|
      Dir.mktmpdir do |directory|
        records = Marshal.load(Marshal.dump(branched_session))
        set_native_cost(records, cost)
        output = report('--host', 'pi', '--file', write_session(directory, records))
        assert_partial_native_cost(output)
      end
    end
  end

  private

  def assert_partial_native_cost(output)
    assert_current_row(output)
    assert_metric output, 'USD estimate', '$0.000100 (partial)'
    assert_includes output, 'Pi recorded native nominal USD'
    assert_includes output, 'Partial estimate: 1 of 2 responses unpriced (Native nominal cost unavailable).'
    refute_includes output, 'SENSITIVE'
  end

  def assert_unknown_pi(output)
    assert_includes output, 'Pi source versions: UNKNOWN'
    assert_includes output, 'Responses: UNKNOWN'
    refute_includes output, 'Codex source versions'
    refute_includes output, '| 300 |'
  end
end
