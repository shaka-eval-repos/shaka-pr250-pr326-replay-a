# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'

module ClaudeUsageFixture
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  COMMIT = 'a' * 40
  SESSION = '00000000-0000-4000-8000-000000000002'
  NO_HOST = { 'PI_CODING_AGENT' => nil, 'CODEX_THREAD_ID' => nil, 'CLAUDE_CODE_SESSION_ID' => nil,
              'CURSOR_CONVERSATION_ID' => nil }.freeze
  PRINT_USAGE = { input_tokens: 100, cache_read_input_tokens: 40, cache_creation_input_tokens: 7,
                  output_tokens: 20, output_tokens_details: { thinking_tokens: 5 }, speed: 'standard',
                  server_tool_use: { web_search_requests: 0 },
                  cache_creation: { ephemeral_5m_input_tokens: 3, ephemeral_1h_input_tokens: 4 } }.freeze

  private

  def prompt(turn, text = 'SENSITIVE-PROMPT')
    { type: 'user', sessionId: SESSION, promptId: turn, message: { role: 'user', content: text } }
  end

  def reply(id, input, output: 20, model: 'claude-test', usage: {})
    { type: 'assistant', sessionId: SESSION, version: '2.1.270', effort: 'high', timestamp: '2026-09-14T12:00:00Z',
      message: { id: id, model: model, content: [{ type: 'text', text: 'SENSITIVE-OUTPUT' }],
                 usage: { input_tokens: input, cache_read_input_tokens: 40, cache_creation_input_tokens: 7,
                          output_tokens: output,
                          output_tokens_details: { thinking_tokens: 5 } }.merge(usage) } }
  end

  def priced_reply(id, input, **overrides)
    reply(id, input, model: 'claude-opus-5',
                     usage: { speed: 'standard', server_tool_use: { web_search_requests: 0 },
                              cache_creation: { ephemeral_5m_input_tokens: 3,
                                                ephemeral_1h_input_tokens: 4 } }, **overrides)
  end

  def transcript(directory, name, records)
    path = File.join(directory, 'projects', 'repo', name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{records.map { |record| JSON.generate(record) }.join("\n")}\n")
    path
  end

  def print_result_file(directory, extra = {})
    path = File.join(directory, 'review.json')
    payload = { type: 'result', subtype: 'success', is_error: false, session_id: SESSION,
                result: 'SENSITIVE-REVIEW-PROSE', usage: PRINT_USAGE,
                modelUsage: { 'claude-opus-5[1m]' => { 'canonicalModel' => 'claude-opus-5' } } }
    File.write(path, JSON.generate(payload.merge(extra)))
    path
  end

  def report(*, environment: {})
    output, error, status = Open3.capture3(NO_HOST.merge(environment), COMMAND, 'usage', '--commit', COMMIT,
                                           '--contribution', 'implementation', *)
    assert_predicate status, :success?, error
    output
  end

  def discovered(directory)
    report(environment: { 'CLAUDE_CODE_SESSION_ID' => SESSION, 'CLAUDE_CONFIG_DIR' => directory })
  end
end

class ClaudeUsageTest < Minitest::Test
  include ClaudeUsageFixture

  # Local Claude review is invoked with -p JSON, not a session transcript.
  # If that file is ignored, the adversarial pass cannot be priced.
  def test_print_mode_result_json_counts_as_one_review_response
    Dir.mktmpdir do |directory|
      output = report('--host', 'claude-code', '--file', print_result_file(directory),
                      '--contribution', 'review')
      assert_includes output, "#{COMMIT} / review"
      assert_metric output, 'Input', 100
      assert_metric output, 'Routed model', 'claude-opus-5'
      assert_metric output, 'USD estimate', '$0.001079'
      assert_includes output.split('<details>').first, 'Local adversarial reviewer usage: included below'
      refute_includes output, 'SENSITIVE'
    end
  end

  # Aggregate tokens billed at whichever modelUsage key JSON listed first would
  # silently underprice an Opus+Haiku review.
  def test_print_mode_with_two_models_does_not_guess_a_rate
    Dir.mktmpdir do |directory|
      extra = { modelUsage: { 'claude-haiku-4-5' => { 'canonicalModel' => 'claude-haiku-4-5' },
                              'claude-opus-5[1m]' => { 'canonicalModel' => 'claude-opus-5' } } }
      output = report('--host', 'claude-code', '--file', print_result_file(directory, extra),
                      '--contribution', 'review')
      assert_metric output, 'Routed model', 'UNKNOWN'
      assert_metric output, 'USD estimate', 'UNKNOWN'
    end
  end

  # A null sibling under a second modelUsage key would still leave one Hash value.
  def test_print_mode_with_a_null_model_usage_sibling_does_not_guess_a_rate
    Dir.mktmpdir do |directory|
      extra = { modelUsage: { 'claude-opus-5[1m]' => { 'canonicalModel' => 'claude-opus-5' },
                              'claude-haiku-4-5' => nil } }
      output = report('--host', 'claude-code', '--file', print_result_file(directory, extra),
                      '--contribution', 'review')
      assert_metric output, 'Routed model', 'UNKNOWN'
      assert_metric output, 'USD estimate', 'UNKNOWN'
    end
  end

  # first.strip on a binary first line raises before parse's EncodingError handler.
  def test_invalid_utf8_file_is_unreadable_not_a_crash
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'review.json')
      File.binwrite(path, "{\xFF\n")
      output = report('--host', 'claude-code', '--file', path, '--contribution', 'review')
      assert_includes output, 'Unreadable or unidentifiable records'
    end
  end

  def test_counts_the_final_streamed_usage_of_each_response_in_the_latest_turn
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('old'), reply('m0', 900), prompt('new'),
                                                     reply('m1', 100, output: 2), reply('m1', 100), reply('m2', 200)])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'Input', 300
      assert_includes output, '2 responses'
      assert_includes output, 'Claude Code source versions: 2.1.270'
      assert_includes output, 'Anthropic input excludes cached input and cache writes'
      refute_match(/900|SENSITIVE/, without_usage_identity(output))
    end
  end

  def test_discovers_the_session_with_only_the_subagents_of_its_latest_turn
    Dir.mktmpdir do |directory|
      transcript(directory, "#{SESSION}.jsonl", [prompt('old'), reply('m0', 900), prompt('new'), reply('m1', 100)])
      transcript(directory, "#{SESSION}/subagents/agent-new.jsonl", [prompt('new'), reply('s1', 200)])
      transcript(directory, "#{SESSION}/subagents/agent-old.jsonl", [prompt('old'), reply('s0', 800)])
      output = discovered(directory)
      assert_metric output, 'Input', 300
      assert_includes output, 'latest turn of the session'
      refute_includes output, SESSION
    end
  end

  def test_column_headers_use_routed_model_when_provider_and_configured_model_match
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('new'),
                                                     reply('m1', 100, model: 'claude-sonnet-5'),
                                                     reply('m2', 200, model: 'claude-opus-5')])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'Metric', 'claude-sonnet-5', 'claude-opus-5'
      refute_includes output, 'anthropic-1'
    end
  end

  def test_selects_all_turns_or_explicit_turns
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('old'), reply('m0', 900), prompt('new'), reply('m1', 100)])
      assert_includes report('--host', 'claude-code', '--file', file, '--all-turns'), '| 1000 |'
      assert_includes report('--host', 'claude-code', '--file', file, '--turn', 'old'), '| 900 |'
    end
  end

  def test_repeated_sources_count_once_and_conflicting_copies_are_unknown
    Dir.mktmpdir do |directory|
      first = transcript(directory, 'first.jsonl', [prompt('new'), reply('m1', 100)])
      second = transcript(directory, 'second.jsonl', [prompt('new'), reply('m1', 999)])
      assert_includes report('--host', 'claude-code', '--file', first, '--file', first), '| 100 |'
      output = report('--host', 'claude-code', '--file', first, '--file', second)
      assert_includes output, 'Conflicting response copies'
      refute_includes output, '| 100 |'
    end
  end
end

class ClaudeUsageFailuresTest < Minitest::Test
  include ClaudeUsageFixture

  def test_another_session_or_a_transcript_without_prompt_ids_is_unknown
    Dir.mktmpdir do |directory|
      other = { type: 'user', sessionId: 'other', promptId: 'new' }
      transcript(directory, "#{SESSION}.jsonl", [other, reply('m1', 100)])
      assert_includes discovered(directory), 'Responses: UNKNOWN'
      file = transcript(directory, 'old-format.jsonl', [{ type: 'user' }, reply('m1', 100)])
      assert_includes report('--host', 'claude-code', '--file', file), 'Responses: UNKNOWN'
    end
  end

  def test_malformed_values_stay_unknown_without_leaking
    Dir.mktmpdir do |directory|
      bad = reply('m1', 100, model: '<b>SENSITIVE</b>')
      bad[:message][:usage] = 'SENSITIVE'
      file = transcript(directory, 'session.jsonl', [prompt('new'), bad])
      File.write(file, '{"SENSITIVE-TRUNCATED', mode: 'a')
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'Input', 'UNKNOWN'
      assert_includes output, 'Unreadable or unidentifiable records'
      refute_includes output, 'SENSITIVE'
    end
  end

  def test_reads_utf8_under_a_c_locale_and_reports_invalid_bytes_as_unreadable
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('new', 'Café — SENSITIVE'), reply('m1', 100)])
      File.write(file, "\xFF\n".b, mode: 'ab')
      output = report('--host', 'claude-code', '--file', file, environment: { 'LC_ALL' => 'C', 'LANG' => 'C' })
      assert_includes output, '| 100 |'
      assert_includes output, 'Unreadable or unidentifiable records'
    end
  end

  def test_all_turns_excludes_and_discloses_responses_without_a_turn
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [reply('m0', 900), { type: 'user', promptId: '  ' },
                                                     reply('m1', 800), prompt('new'), reply('m2', 100)])
      output = report('--host', 'claude-code', '--file', file, '--all-turns')
      assert_includes output, '| 100 |'
      assert_includes output.split('<details>').first, 'Unreadable or unidentifiable records'
      refute_match(/900|800/, without_usage_identity(output))
    end
  end

  def test_discovery_skips_an_unreadable_line_before_the_session_id
    Dir.mktmpdir do |directory|
      path = transcript(directory, "#{SESSION}.jsonl", [prompt('new'), reply('m1', 100)])
      File.write(path, "{broken\n#{File.read(path)}")
      assert_includes discovered(directory), '| 100 |'
    end
  end

  # A user record's uuid looks like the turn ID but is not; an empty table would hide that.
  # A turn whose only response lacks an ID has no readable response either.
  def test_turn_that_matches_no_response_fails_and_names_the_expected_field
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('old'), reply('m0', 900), prompt('new'), reply(nil, 1)])
      output, error, status = Open3.capture3(NO_HOST, COMMAND, 'usage', '--commit', COMMIT, '--contribution',
                                             'implementation', '--host', 'claude-code', '--file', file,
                                             '--turn', 'old', '--turn', 'new', '--turn', 'user-uuid')
      refute_predicate status, :success?
      assert_empty output
      assert_match(/new, user-uuid .*promptId/, error)
    end
  end

  # Conflict reduction clears a response's turn; the selected turn still existed.
  def test_explicit_turns_with_conflicting_copies_report_the_conflict
    Dir.mktmpdir do |directory|
      first = transcript(directory, 'first.jsonl', [prompt('new'), reply('m1', 100)])
      second = transcript(directory, 'second.jsonl', [prompt('new'), reply('m1', 999)])
      moved = transcript(directory, 'moved.jsonl', [prompt('other'), reply('m1', 100)])
      [[second, '--turn', 'new'], [moved, '--turn', 'new', '--turn', 'other']].each do |other, *turns|
        output = report('--host', 'claude-code', '--file', first, '--file', other, *turns)
        assert_includes output, 'Conflicting response copies'
      end
    end
  end

  def test_both_host_contexts_require_an_explicit_host
    environment = { 'PI_CODING_AGENT' => nil, 'CODEX_THREAD_ID' => SESSION,
                    'CLAUDE_CODE_SESSION_ID' => SESSION }
    output, error, status = Open3.capture3(environment, COMMAND, 'usage', '--commit', COMMIT,
                                           '--contribution', 'implementation')
    refute_predicate status, :success?
    assert_empty output
    assert_includes error, 'shaka usage:'
  end
end

class ClaudeUsagePriceTest < Minitest::Test
  include ClaudeUsageFixture

  # Reports one response whose recorded usage the block adjusts first.
  def served
    Dir.mktmpdir do |directory|
      reply = priced_reply('m1', 100)
      yield reply[:message][:usage]
      report('--host', 'claude-code', '--file', transcript(directory, 'session.jsonl', [prompt('new'), reply]))
    end
  end

  def test_a_standard_speed_session_reports_a_dollar_estimate_from_published_rates
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('new'), priced_reply('m1', 100)])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'USD estimate', '$0.001079'
      assert_metric output, 'Metric', 'claude-opus-5'
      assert_includes output, 'Anthropic API list prices'
      refute_includes output, 'Cache-exclusive input is unpriced'
    end
  end

  def test_the_token_table_keeps_its_published_columns_and_its_own_summary
    Dir.mktmpdir do |directory|
      file = transcript(directory, 'session.jsonl', [prompt('new'), priced_reply('m1', 100)])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'Cache writes', 7
      refute_includes output, 'cache_write_1h'
      assert_includes output, '<summary>Token detail</summary>'
      refute_includes output, '<summary>Native usage</summary>'
      assert_includes output, 'Native usage is PARTIAL'
    end
  end

  def test_a_cache_creation_split_that_contradicts_the_total_is_not_priced
    Dir.mktmpdir do |directory|
      contradictory = priced_reply('m1', 100)
      contradictory[:message][:usage][:cache_creation][:ephemeral_5m_input_tokens] = 1
      file = transcript(directory, 'session.jsonl', [prompt('new'), contradictory])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'USD estimate', 'UNKNOWN'
      assert_includes output, 'Inconsistent token subsets'
      assert_metric output, 'Cache writes', 7
    end
  end

  def test_a_web_search_adds_its_published_per_request_charge
    Dir.mktmpdir do |directory|
      searched = priced_reply('m1', 100)
      searched[:message][:usage][:server_tool_use][:web_search_requests] = 2
      file = transcript(directory, 'session.jsonl', [prompt('new'), searched])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'USD estimate', '$0.021079'
    end
  end

  def test_a_response_that_only_fetched_is_priced_on_its_tokens
    Dir.mktmpdir do |directory|
      fetched = priced_reply('m1', 100)
      fetched[:message][:usage][:server_tool_use] = { web_fetch_requests: 1 }
      file = transcript(directory, 'session.jsonl', [prompt('new'), fetched])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'USD estimate', '$0.001079'
    end
  end

  def test_an_absent_server_tool_group_is_no_charge
    assert_metric served { |usage| usage.delete(:server_tool_use) }, 'USD estimate', '$0.001079'
  end

  def test_an_unreadable_server_tool_group_is_a_gap_not_a_zero
    output = served { |usage| usage[:server_tool_use] = 'malformed' }
    assert_metric output, 'USD estimate', 'UNKNOWN'
    assert_includes output, 'Server tool usage UNKNOWN'
  end

  def test_published_fast_mode_is_priced_at_its_dedicated_rate
    Dir.mktmpdir do |directory|
      fast = priced_reply('m1', 100)
      fast[:message][:usage][:speed] = 'fast'
      file = transcript(directory, 'session.jsonl', [prompt('new'), fast])
      output = report('--host', 'claude-code', '--file', file)
      assert_metric output, 'USD estimate', '$0.002158'
      assert_includes output, 'fast mode is priced for Opus models with a published rate'
    end
  end
end

# The report identity names only responses whose token counters were read.
class ClaudeUsageIdentityTest < Minitest::Test
  include ClaudeUsageFixture

  # Break: a web-search count of zero made a response with no token counters count as measured.
  def test_response_without_token_counters_is_left_out_of_the_identity
    Dir.mktmpdir do |directory|
      empty = reply('msg-empty', 0)
      empty[:message][:usage] = { server_tool_use: { web_search_requests: 0 } }
      path = transcript(directory, 'session.jsonl', [prompt('turn'), empty, reply('msg-full', 100)])
      identity = JSON.parse(report('--host', 'claude-code', '--file', path)[/\A<!-- shaka:usage (.*) -->\n/, 1])
      assert_equal 1, identity['responses'].size
    end
  end

  def print_identity(*files)
    output = report('--host', 'claude-code', *files.flat_map { |file| ['--file', file] })
    [JSON.parse(output[/\A<!-- shaka:usage (.*) -->\n/, 1])['responses'], output]
  end

  # Break: resumed print runs share a session ID, so a later run's report replaced an earlier one.
  def test_resumed_print_runs_have_separate_identities
    Dir.mktmpdir do |directory|
      first, = print_identity(print_result_file(directory))
      resumed, = print_identity(print_result_file(directory, usage: PRINT_USAGE.merge(output_tokens: 21)))
      refute_equal first, resumed
    end
  end

  # Break: scoping the identity by file made identical copies conflict and lose their counters.
  def test_identical_print_result_copies_still_count_once
    Dir.mktmpdir do |directory|
      original = print_result_file(directory)
      copy = File.join(directory, 'copy.json')
      FileUtils.cp(original, copy)
      responses, output = print_identity(original, copy)
      assert_equal [1, print_identity(original).first], [responses.size, responses]
      assert_metric output, 'Input', 100
    end
  end
end

class ClaudeUsageSinceTimeTest < Minitest::Test
  include ClaudeUsageFixture

  def test_start_time_refuses_an_aggregate_print_result
    Dir.mktmpdir do |directory|
      file = print_result_file(directory, timestamp: '2026-09-14T12:00:01Z')
      output, error, status = Open3.capture3(NO_HOST, COMMAND, 'usage', '--host', 'claude-code', '--file', file,
                                             '--commit', COMMIT, '--contribution', 'review',
                                             '--since-time', '2026-09-14T12:00:00Z')

      refute_predicate status, :success?
      assert_equal '', output
      assert_includes error, '--since-time cannot split an aggregate usage record'
    end
  end
end
