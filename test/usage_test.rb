# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'time'
require 'shaka/publication/publication'

module UsageFixture
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  COMMIT = 'a' * 40
  THREAD = '00000000-0000-0000-0000-000000000001'
  NATIVE_OPENAI = <<~TABLE.chomp
    | Metric | openai |
    | --- | --- |
    | Provider | openai |
    | Configured model | gpt-test |
    | Routed model | UNKNOWN |
    | Effort | high |
    | Input | 100 |
    | Cached input | 40 |
    | Output | 20 |
    | Reasoning output | 5 |
    | Cache writes | UNKNOWN |
    | Native total | UNKNOWN |
  TABLE

  private

  def context(turn)
    { type: 'turn_context', payload: { turn_id: turn, model: 'gpt-test', effort: 'high' } }
  end

  def usage(response, turn, input)
    { type: 'token_usage_record', timestamp: '2026-09-14T12:00:00Z',
      payload: { response_id: response, turn_id: turn,
                 usage: { input_tokens: input, cached_input_tokens: 40,
                          output_tokens: 20, reasoning_output_tokens: 5 },
                 thread_token_usage: { input_tokens: 9999 } } }
  end

  def run_report(records, *, **options)
    Dir.mktmpdir do |directory|
      file = write_records(directory, records, options)
      environment = host_environment(directory).merge(options.fetch(:environment, {}))
      sources = options[:discover] ? [] : ['--file', file] * options.fetch(:copies, 1)
      output, error, status = Open3.capture3(environment, COMMAND, 'usage', *sources, '--commit', COMMIT,
                                             '--contribution', options[:contribution] || 'implementation', *)
      assert_predicate status, :success?, error
      output
    end
  end

  def host_environment(directory)
    { 'PI_CODING_AGENT' => nil, 'CODEX_HOME' => directory, 'CODEX_THREAD_ID' => THREAD,
      'CLAUDE_CODE_SESSION_ID' => nil, 'CURSOR_CONVERSATION_ID' => nil }
  end

  def write_records(directory, records, options)
    folder = File.join(directory, 'sessions', '2026', '09', '14')
    FileUtils.mkdir_p(folder)
    file = File.join(folder, "rollout-#{THREAD}.jsonl")
    metadata = { type: 'session_meta', payload: { id: options.fetch(:identity, THREAD), model_provider: 'openai',
                                                  cli_version: '0.154.0-alpha.6.2' } }
    metadata = options.fetch(:metadata, metadata)
    File.write(file, "#{[metadata, *records].map { |record| JSON.generate(record) }.join("\n")}\n")
    File.write(file, options.fetch(:raw_tail, ''), mode: 'a')
    file
  end

  def priced_context(turn, model, effort: 'high')
    context(turn).tap { |setting| setting[:payload].merge!(model: model, effort: effort) }
  end

  def priced_usage(id, turn, input, **tokens)
    usage(id, turn, input).tap do |response|
      response[:payload][:usage].merge!(cached_input_tokens: tokens.fetch(:cached, 0),
                                        cache_write_input_tokens: tokens.fetch(:writes, 0),
                                        output_tokens: tokens.fetch(:output, 20), reasoning_output_tokens: 0)
    end
  end
end

class UsageTest < Minitest::Test
  include UsageFixture

  def test_native_usage_table_uses_metric_rows_instead_of_a_wide_provider_row
    report = run_report([context('current'), usage('current', 'current', 100)])
    native = report[%r{<details>.*?</details>}m]
    refute_includes native, '| Provider | Configured model | Routed model | Effort | Input |'
    assert_includes native, NATIVE_OPENAI
  end

  def test_counts_each_response_once_in_latest_turn_without_adding_cumulative_snapshots
    records = [context('old'), usage('old-response', 'old', 900), context('current'),
               usage('response-1', 'current', 100), usage('response-1', 'current', 100),
               usage('response-2', 'current', 200),
               { type: 'event_msg', payload: { type: 'token_count', info: { total_tokens: 9999 } } }]
    report = run_report(records)
    assert_metric report, 'Input', 300
    assert_includes report, 'gpt-test'
    assert_includes report, 'high'
    assert_includes report, '2 responses'
    refute_includes without_usage_identity(report), '9999'
  end

  def test_explicit_turns_across_resumed_files_are_shared_without_recounting_responses
    records = [context('old'), usage('first', 'old', 900), context('current'), usage('second', 'current', 100)]
    report = run_report(records, '--turn', 'old', '--turn', 'current',
                        '--commit', "#{COMMIT},#{'b' * 40}", copies: 2)
    assert_metric report, 'Input', 1000
    assert_includes report, 'SHARED'
    assert_includes report, '2 responses'
    assert_includes report, '2026-09-14T12:00:00Z'
    assert_includes report, 'PARTIAL'
    assert_includes report, 'External reviewer/tool-model usage: UNKNOWN'
  end

  def test_missing_fields_stay_unknown_and_each_turn_keeps_its_configured_model
    incomplete = usage('first', 'old', 100)
    incomplete[:payload][:usage].delete(:cached_input_tokens)
    changed = context('current')
    changed[:payload].merge!(model: 'gpt-other', effort: 'low')
    records = [context('old'), incomplete, changed, usage('second', 'current', 200)]
    report = run_report(records, '--turn', 'old', '--turn', 'current')
    assert_metric report, 'Configured model', 'gpt-test', 'gpt-other'
    assert_metric report, 'Input', 100, 200
    assert_metric report, 'Cached input', 'UNKNOWN', 40
    assert_includes report, '0.154.0-alpha.6.2'
  end

  def test_preserves_native_cache_writes_and_total_without_adding_subsets
    response = usage('current', 'current', 100)
    response[:payload][:usage].merge!(cache_write_input_tokens: 7, total_tokens: 120)
    report = run_report([context('current'), response])
    assert_metric report, 'Input', 100
    assert_metric report, 'Cache writes', 7
    assert_metric report, 'Native total', 120
    assert_includes report, 'Native total'
  end

  def test_unidentifiable_or_truncated_records_cannot_inflate_usage_or_leak_private_content
    unidentifiable = usage('unknown', 'current', 9900)
    unidentifiable[:payload].delete(:response_id)
    report = run_report([context('current'), usage('counted', 'current', 100), unidentifiable],
                        raw_tail: '{"private-prompt": "SENSITIVE-INCOMPLETE')
    assert_metric report, 'Input', 100
    assert_metric report, 'Cached input', 40
    assert_includes report, 'Unreadable or unidentifiable records'
    refute_includes report, 'SENSITIVE'
    refute_includes without_usage_identity(report), '9900'
  end

  def test_all_turns_counts_a_dedicated_task_once_and_discloses_scope
    records = [context('old'), usage('old', 'old', 900), context('current'), usage('current', 'current', 100)]
    report = run_report(records, '--all-turns', copies: 2)
    assert_metric report, 'Input', 1000
    assert_includes report.split('<details>').first, 'all turns'
    refute_includes report, 'old-response'
  end

  def test_default_visibly_discloses_that_earlier_turns_are_excluded
    report = run_report([context('old'), usage('old', 'old', 900),
                         context('current'), usage('current', 'current', 100)], discover: true)
    assert_includes report.split('<details>').first, 'latest turn only'
  end

  def test_discovers_current_thread_from_host_context_and_uses_only_latest_turn
    report = run_report([context('old'), usage('old', 'old', 900),
                         context('current'), usage('current', 'current', 100)], discover: true)
    assert_metric report, 'Input', 100
    assert_includes report, 'host context'
    assert_includes report, 'SHARED'
    refute_includes report, THREAD
  end

  # Break caught: an unreadable replacement context left the earlier model in place,
  # so later responses were priced at a rate the session may no longer have used.
  def test_unreadable_line_does_not_leave_earlier_settings_on_later_responses
    replacement = %({"type":"turn_context","payload":{"turn_id":"current","model":"gpt-\xFF"}}\n).b +
                  "#{JSON.generate(usage('current', 'current', 50))}\n"
    report = run_report([context('current')], raw_tail: replacement)
    assert_metric report, 'Configured model', 'UNKNOWN'
    assert_metric report, 'Input', 50
  end
end

class UsageSinceTimeTest < Minitest::Test
  include UsageFixture

  START = Time.iso8601('2026-09-14T12:00:00Z')

  def test_counts_only_later_responses_in_a_shared_session
    records = [context('old'), timed_usage('previous-task', 'old', 900, START - 1),
               context('current'), timed_usage('current-task', 'current', 200, START + 1)]

    report = run_report(records, '--since-time', START.iso8601)

    assert_metric report, 'Input', 200
    assert_includes report, '1 responses'
    assert_includes report, "responses at or after #{START.iso8601} (whole-second sources include the cutoff second)"
    assert_selected_identity(report)
  end

  def test_keeps_a_whole_second_response_in_the_cutoff_second
    records = [context('current'), timed_usage('earlier', 'current', 900, START - 1),
               timed_usage('current', 'current', 200, START)]

    report = run_report(records, '--since-time', (START + 0.5).iso8601(3))

    assert_metric report, 'Input', 200
    assert_selected_identity(report)
  end

  def test_records_offset_timestamp_interval_in_utc
    record = usage('offset', 'current', 200)
    record[:timestamp] = '2026-09-14T13:00:01+01:00'

    report = run_report([context('current'), record], '--since-time', START.iso8601)

    assert_includes report, '2026-09-14T12:00:01Z through 2026-09-14T12:00:01Z'
    identity = JSON.parse(report.match(/<!-- shaka:usage (\{[^\n]*\}) -->/)[1])
    assert_equal '2026-09-14T12:00:01Z', identity.fetch('from')
    assert_equal '2026-09-14T12:00:01Z', identity.fetch('to')
  end

  def test_orders_mixed_precision_interval_in_report_and_identity
    whole = usage('whole', 'current', 100)
    whole[:timestamp] = '2026-09-14T12:00:01Z'
    precise = usage('precise', 'current', 200)
    precise[:timestamp] = '2026-09-14T12:00:01.500Z'

    report = run_report([context('current'), whole, precise], '--since-time', START.iso8601)

    assert_metric report, 'Input', 300
    assert_includes report, '2026-09-14T12:00:01Z through 2026-09-14T12:00:01.500Z'
    identity = JSON.parse(report.match(/<!-- shaka:usage (\{[^\n]*\}) -->/)[1])
    assert_equal ['2026-09-14T12:00:01Z', '2026-09-14T12:00:01.500Z'], identity.values_at('from', 'to')
  end

  def test_rejects_an_invalid_start_time
    _output, error, status = Open3.capture3(COMMAND, 'usage', '--commit', COMMIT,
                                            '--contribution', 'implementation', '--since-time', 'bad')

    refute_predicate status, :success?
    assert_includes error, 'invalid options'
  end

  def test_rejects_start_time_combined_with_other_turn_selection
    [['--all-turns'], ['--turn', 'current']].each do |selection|
      _output, error, status = Open3.capture3(COMMAND, 'usage', '--commit', COMMIT,
                                              '--contribution', 'implementation', '--since-time', START.iso8601,
                                              *selection)
      refute_predicate status, :success?
      assert_includes error, 'invalid options'
    end
  end

  def test_refuses_an_unstamped_response_instead_of_reporting_zero
    _output, error, status = unstamped_report

    refute_predicate status, :success?
    assert_includes error, '--since-time needs a zoned timestamp'
  end

  def test_refuses_a_start_time_after_every_response
    record = timed_usage('earlier', 'current', 100, START - 1)
    output, error, status = run_raw_report([context('current'), record], START.iso8601)

    refute_predicate status, :success?
    assert_equal '', output
    assert_includes error, '--since-time selected no responses'
  end

  def test_refuses_a_response_timestamp_without_a_timezone
    Dir.mktmpdir do |directory|
      record = usage('unplaced', 'current', 100)
      record[:timestamp] = '2026-09-14T12:00:01'
      file = write_records(directory, [context('current'), record], {})
      _output, error, status = Open3.capture3(host_environment(directory), COMMAND, 'usage', '--file', file,
                                              '--commit', COMMIT, '--contribution', 'implementation',
                                              '--since-time', START.iso8601)

      refute_predicate status, :success?
      assert_includes error, '--since-time needs a zoned timestamp'
    end
  end

  private

  def assert_selected_identity(report)
    identity = JSON.parse(report.match(/<!-- shaka:usage (\{[^\n]*\}) -->/)[1])
    assert_equal 1, identity.fetch('responses').size
    assert identity.fetch('complete')
  end

  def timed_usage(id, turn, input, at)
    usage(id, turn, input).tap { |response| response[:timestamp] = at.iso8601 }
  end

  def unstamped_report
    record = usage('unplaced', 'current', 100)
    record.delete(:timestamp)
    run_raw_report([context('current'), record], START.iso8601)
  end

  def run_raw_report(records, start)
    Dir.mktmpdir do |directory|
      file = write_records(directory, records, {})
      Open3.capture3(host_environment(directory), COMMAND, 'usage', '--file', file,
                     '--commit', COMMIT, '--contribution', 'implementation', '--since-time', start)
    end
  end
end

class UsageReviewCoverageTest < Minitest::Test
  include UsageFixture

  # A review snapshot that counted tokens but still said only "external reviewer
  # UNKNOWN" hid the local adversarial pass that those numbers belong to.
  # Break caught: a shell without a UTF-8 locale crashed on the first non-ASCII
  # byte in a Codex session, so review usage could not be reported at all.
  def test_reads_utf8_under_a_c_locale_and_reports_invalid_bytes_as_unreadable
    records = [{ type: 'response_item', payload: { text: 'Café — SENSITIVE' } }, context('current'),
               usage('current', 'current', 100)]
    invalid = %({"type":"turn_context","payload":{"turn_id":"other","model":"gpt-\xFF"}}\n).b +
              "#{JSON.generate(usage('other', 'other', 900))}\n"
    report = run_report(records, raw_tail: invalid, environment: { 'LC_ALL' => 'C', 'LANG' => 'C' })
    assert_metric report, 'Input', 100
    assert_includes report, 'Unreadable or unidentifiable records'
    refute_includes report, 'SENSITIVE'
  end

  def test_review_contribution_with_records_includes_local_adversarial_usage
    report = run_report([context('current'), usage('current', 'current', 100)], '--contribution', 'review')
    header = report.split('<details>').first
    assert_includes report, "#{COMMIT} / review"
    assert_includes header, 'Local adversarial reviewer usage: included below'
    assert_includes header, 'External reviewer/tool-model usage: UNKNOWN'
    refute_includes header, 'Local adversarial reviewer usage: UNKNOWN'
    assert_metric report, 'Input', 100
  end

  # Implementation tokens are not the adversarial pass. Claiming they are would
  # hide a missing review snapshot behind a green usage table.
  def test_implementation_snapshot_does_not_count_as_local_review
    header = run_report([context('current'), usage('current', 'current', 100)]).split('<details>').first
    assert_includes header, 'Local adversarial reviewer usage: UNKNOWN'
  end

  # Conflicting copies keep a response row whose usage is empty. Calling that
  # "included below" would advertise reviewer tokens that every metric lists as UNKNOWN.
  def test_review_contribution_with_uncountable_records_does_not_claim_inclusion
    report = run_report([context('current'), usage('replayed', 'current', 100),
                         usage('replayed', 'current', 200)], '--contribution', 'review')
    header = report.split('<details>').first
    assert_includes header, 'Local adversarial reviewer usage: UNKNOWN'
    refute_includes header, 'included below'
  end

  # The table needs every record in a group to carry a field. A header that looks
  # only at per-record fields can say "included below" over a table of UNKNOWN cells.
  def test_review_header_follows_printed_metric_cells
    first = usage('a', 'current', 100)
    first[:payload][:usage] = { input_tokens: 100 }
    second = usage('b', 'current', 20)
    second[:payload][:usage] = { output_tokens: 20 }
    header = run_report([context('current'), first, second], '--contribution', 'review').split('<details>').first
    assert_includes header, 'Local adversarial reviewer usage: UNKNOWN'
    refute_includes header, 'included below'
  end
end

class UsageFailuresTest < Minitest::Test
  include UsageFixture

  def test_all_turns_discloses_records_excluded_for_invalid_turn_identity
    [nil, '', '  ', 42].each do |turn|
      report = run_report([context('current'), usage('counted', 'current', 100),
                           usage('unattributed', turn, 9900)], '--all-turns')
      assert_includes report.split('<details>').first, 'Unreadable or unidentifiable records'
      assert_includes report, '| 100 |'
      refute_includes without_usage_identity(report), '9900'
    end
  end

  def test_missing_or_invalid_latest_turn_does_not_count_unattributed_responses
    [nil, '', 42].each do |turn|
      records = turn.nil? ? [] : [context(turn)]
      response = usage('unattributed', turn, 100)
      response[:payload].delete(:turn_id) if turn.nil?
      report = run_report([*records, response])
      assert_includes report, 'Responses: UNKNOWN'
      refute_includes report, '| 100 |'
    end
  end

  def test_discovery_handles_unsupported_session_metadata_as_unknown
    [nil, [], { type: 'session_meta', payload: [] }].each do |metadata|
      report = run_report([context('current'), usage('current', 'current', 100)], discover: true, metadata: metadata)
      assert_includes report, 'Responses: UNKNOWN'
    end
  end

  def test_malformed_token_payloads_stay_unknown_without_printing_the_bad_data
    [nil, 42, [], 'SENSITIVE'].each do |bad_usage|
      response = usage('current', 'current', 100)
      response[:payload][:usage] = bad_usage
      report = run_report([context('current'), response])
      assert_metric report, 'Effort', 'high'
      assert_metric report, 'Input', 'UNKNOWN'
      refute_includes report, 'SENSITIVE'
    end
  end

  def test_unavailable_native_records_and_unconfirmed_identity_report_unknown_instead_of_zero
    unsupported = [{ type: 'event_msg', payload: { type: 'token_count', info: { total_tokens: 9999 } } }]
    [run_report(unsupported),
     run_report([context('current'), usage('wrong-owner', 'current', 100)],
                discover: true, identity: 'different-thread')].each do |report|
      assert_includes report, 'Responses: UNKNOWN'
      refute_includes report, '0 responses'
      refute_includes report, '| 100 |'
    end
  end

  def test_public_report_rejects_unstructured_metadata_and_keeps_transcripts_private
    setting = context('current')
    setting[:payload].merge!(model: '<b>SENSITIVE-MODEL</b>', effort: "high\nSENSITIVE-EFFORT")
    response = usage('current', 'current', 100)
    response[:timestamp] = '/private/SENSITIVE-PATH'
    report = run_report([setting, response,
                         { type: 'response_item', payload: { content: 'SENSITIVE-PROMPT' } }])
    assert_metric report, 'Input', 100
    assert_includes report, 'source interval: UNKNOWN'
    refute_includes report, 'SENSITIVE'
    refute_includes report, '/private/'
  end

  def test_conflicting_copies_of_a_response_mark_counts_unknown
    report = run_report([context('current'), usage('replayed', 'current', 100), usage('replayed', 'current', 200)])
    assert_metric report, 'USD estimate', 'UNKNOWN'
    assert_includes report, 'Conflicting response copies'
    refute_includes report, '| 100 |'
  end

  def test_duplicate_attribution_conflicts_are_unknown_in_either_source_order
    original = context('current')
    changed = context('current')
    changed[:payload][:model] = 'other-model'
    reports = [[original, changed], [changed, original]].map do |first, second|
      run_report([first, usage('same', 'current', 100), second, usage('same', 'current', 100)])
    end
    assert_equal(*reports.map { |report| without_usage_identity(report) })
    assert_metric reports.first, 'USD estimate', 'UNKNOWN'
    assert_includes reports.first, 'Conflicting response copies'
  end

  def test_usage_without_matching_turn_context_does_not_inherit_another_turns_settings
    [[], [context('old')]].each do |records|
      report = run_report([*records, usage('current', 'current', 100)], '--turn', 'current')
      assert_metric report, 'Provider', 'openai'
      assert_metric report, 'Configured model', 'UNKNOWN'
      assert_metric report, 'Input', 100
    end
  end

  def test_invalid_commit_or_contribution_is_rejected_without_echoing_private_arguments
    [['--commit', '/private/SENSITIVE', '--contribution', 'implementation'],
     ['--commit', COMMIT, '--contribution', 'SENSITIVE'],
     ['--commit', COMMIT, '--contribution', 'implementation', '--all-turns', '--turn', 'old'], []].each do |arguments|
      output, error, status = Open3.capture3(COMMAND, 'usage', *arguments)
      refute_predicate status, :success?
      assert_empty output
      assert_includes error, 'shaka usage:'
      refute_includes error, 'SENSITIVE'
    end
  end
end

class UsageTurnSelectionTest < Minitest::Test
  include UsageFixture

  # Codex selects turns in its own reader, so it needs its own unmatched-turn check.
  def test_codex_turn_that_matches_no_response_fails_and_names_the_expected_field
    Dir.mktmpdir do |directory|
      file = write_records(directory, [context('old'), usage('first', 'old', 900)], {})
      output, error, status = Open3.capture3({ 'CODEX_THREAD_ID' => nil }, COMMAND, 'usage', '--host', 'codex',
                                             '--file', file, '--commit', COMMIT, '--contribution',
                                             'implementation', '--turn', 'typo')
      refute_predicate status, :success?
      assert_empty output
      assert_match(/typo.*turn_id/, error)
    end
  end
end

class MetricAssertTest < Minitest::Test
  def test_rejects_extra_trailing_cells
    assert_raises(Minitest::Assertion) { assert_metric("| Input | 300 | 999 |\n", 'Input', 300) }
    assert_metric("| Input | 300 |\n", 'Input', 300)
  end
end

# Each report carries a hidden identity so later description updates can keep or replace it.
class UsageIdentityTest < Minitest::Test
  include UsageFixture

  # Break: without an identity, a later host cannot tell this report from a refreshed snapshot.
  def test_report_is_marked_with_hashed_response_and_source_identity
    report = run_report([context('current'), usage('r1', 'current', 100), usage('r2', 'current', 100)])
    fields = JSON.parse(report[/\A<!-- shaka:usage (.*) -->\n/, 1])
    assert_equal ['codex', 'implementation', [COMMIT], '2026-09-14T12:00:00Z', '2026-09-14T12:00:00Z'],
                 fields.values_at('host', 'contribution', 'commits', 'from', 'to')
    assert_equal [2, 1], [fields['responses'].uniq.size, fields['sources'].size]
  end

  # Break: a conflicting copy kept its ID with no counters and so covered an earlier measured report.
  def test_identity_lists_only_responses_with_readable_counters
    report = run_report([context('current'), usage('replayed', 'current', 100), usage('replayed', 'current', 200),
                         usage('clean', 'current', 100)])
    assert_equal 1, JSON.parse(report[/\A<!-- shaka:usage (.*) -->\n/, 1])['responses'].size
  end

  # Break: a negative counter rendered UNKNOWN yet counted as measured, so it could cover real usage.
  def test_identity_leaves_out_responses_with_only_negative_counters
    negative = usage('negative', 'current', -1)
    negative[:payload][:usage].merge!(cached_input_tokens: -1, output_tokens: -1, reasoning_output_tokens: -1)
    report = run_report([context('current'), negative, usage('clean', 'current', 100)])
    fields = JSON.parse(report[/\A<!-- shaka:usage (.*) -->\n/, 1])
    assert_equal [1, false], [fields['responses'].size, fields['complete']]
  end

  # A pasted helper report is still a details item. The description takes the usage object.
  def test_description_refuses_a_pasted_usage_report
    [[context('current'), usage('r1', 'current', 100)], [context('current')]].each do |records|
      content = { 'identity' => { 'agent' => 'Codex' }, 'summary' => 'A summary.', 'deployment' => 'none',
                  'table' => { 'columns' => %w[Check], 'rows' => [%w[pass]] }, 'provenance' => provenance,
                  'details' => [{ 'summary' => 'Usage and cost', 'body' => run_report(records) }] }
      error = assert_raises(Shaka::Error) { Shaka::Publication.description(content) }
      assert_includes error.message, 'usage object'
    end
  end

  def provenance
    %w[task_source requested_model requested_effort recommended_model recommended_effort active_model
       active_effort].to_h { |key| [key, 'UNKNOWN'] }.merge('initial_prompt' => 'EXCLUDED', 'task_source' => 'issue')
  end

  def test_report_identity_hides_response_ids_and_closes_the_record
    report = run_report([context('current'), usage('r1', 'current', 100)])
    refute_includes report.lines.first, 'r1'
    assert_equal "<!-- shaka:usage:end -->\n", report.lines.last
  end
end
