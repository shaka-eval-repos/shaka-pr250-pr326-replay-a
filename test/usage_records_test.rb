# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require_relative '../skills/shaka/lib/shaka/usage/usage_records'

# Builds marked usage reports and the descriptions that hold them.
module UsageRecordsFixture
  COMMIT = 'a' * 40

  DEFAULTS = { 'sources' => ['s1'], 'contribution' => 'implementation', 'commits' => [COMMIT], 'complete' => true,
               'from' => '2026-09-14T12:00:00Z', 'to' => '2026-09-14T13:00:00Z' }.freeze

  def record(host, label, **overrides)
    fields = DEFAULTS.merge('host' => host).merge(overrides.transform_keys(&:to_s))
    "#{Shaka::UsageRecords.begin_mark(fields)}\n| Metric | #{label} |\n| --- | --- |\n" \
      "| USD estimate | #{label} |\n\n<details>\n<summary>Token detail</summary>\n\n#{label}\n\n</details>\n" \
      "#{Shaka::UsageRecords::END_MARK}"
  end

  def described(usage_body)
    { 'summary' => 'S', 'details' => [{ 'summary' => 'Usage and cost', 'body' => usage_body }] }
  end

  def existing(*records, outside: '')
    "#{outside}<!-- shaka:begin -->\nS\n\n<details>\n<summary>Usage and cost</summary>\n\n" \
      "#{records.join("\n\n")}\n\n</details>\n<!-- shaka:end -->"
  end

  def carried(existing_body, usage_body)
    content, = Shaka::UsageRecords.carry(described(usage_body), existing_body)
    content['details'].first['body']
  end
end

# A description update must keep usage from earlier hosts, models, and reviews.
class UsageRecordsTest < Minitest::Test
  include UsageRecordsFixture

  # Break: publishing Codex usage after Claude implementation erased the Claude record (#269).
  def test_provider_handoff_keeps_the_earlier_implementation_and_review
    claude = record('claude-code', 'opus-impl', responses: %w[c1 c2])
    review = record('codex', 'codex-review', responses: %w[r1], sources: ['s2'], contribution: 'review')
    body = carried(existing(claude, review), record('codex', 'codex-integration', responses: %w[x1], sources: ['s3']))
    %w[opus-impl codex-review codex-integration].each { |label| assert_includes body, label }
    assert_operator body.index('opus-impl'), :<, body.index('codex-integration')
  end

  # Break: returning to Claude would replace the first Claude snapshot from a disjoint turn.
  def test_return_to_original_provider_keeps_its_disjoint_earlier_turn
    first = record('claude-code', 'claude-turn-1', responses: %w[c1])
    codex = record('codex', 'codex-turn', responses: %w[x1], sources: ['s2'])
    body = carried(existing(first, codex), record('claude-code', 'claude-turn-2', responses: %w[c2]))
    %w[claude-turn-1 codex-turn claude-turn-2].each { |label| assert_includes body, label }
  end

  # Break: a refreshed snapshot of the same responses would publish them twice.
  def test_newer_snapshot_replaces_one_sharing_responses
    old = record('claude-code', 'claude-old', responses: %w[c1 c2])
    body = carried(existing(old), record('claude-code', 'claude-all-turns', responses: %w[c1 c2 c3]))
    refute_includes body, 'claude-old'
    assert_includes body, 'claude-all-turns'
  end

  # Break: a latest-turn snapshot after --all-turns deleted the responses it did not cover.
  def test_partial_overlap_keeps_the_report_holding_uncovered_responses
    old = record('claude-code', 'all-turns', responses: %w[c1 c2])
    body = carried(existing(old), record('claude-code', 'latest-turn', responses: %w[c2 c3]))
    assert_includes body, 'all-turns'
  end

  # Break: a refreshed review in a second usage section left its old snapshot carried into the first.
  def test_reports_in_every_usage_section_count_as_new
    old = record('codex', 'old-review', responses: %w[r1])
    content = described(record('claude-code', 'impl', responses: %w[c1]))
    content['details'] << { 'summary' => 'Review usage', 'body' => record('codex', 'new-review', responses: %w[r1]) }
    carried_content, stats = Shaka::UsageRecords.carry(content, existing(old))
    refute_includes carried_content['details'].map { |item| item['body'] }.join, 'old-review'
    assert_equal 1, stats['replaced']
  end

  # Break: a snapshot whose totals became UNKNOWN from one unreadable response erased measured totals.
  # Break: an integration snapshot for another commit erased the implementation report's attribution.
  def test_replacement_keeps_reports_with_a_different_contribution_or_commits
    old = record('claude-code', 'impl-a', responses: %w[c1])
    other_role = record('claude-code', 'integration', responses: %w[c1 c2], contribution: 'integration')
    assert_includes carried(existing(old), other_role), 'impl-a'
    other_commit = record('claude-code', 'commit-b', responses: %w[c1 c2], commits: ['b' * 40])
    assert_includes carried(existing(old), other_commit), 'impl-a'
    squashed = record('claude-code', 'squashed', responses: %w[c1], commits: [COMMIT, 'c' * 40])
    refute_includes carried(existing(old), squashed), 'impl-a'
  end

  # Break: concurrent work in another session overlapped in time but shares no responses.
  def test_concurrent_sources_without_shared_responses_are_both_kept
    old = record('claude-code', 'implementation', responses: %w[c1])
    body = carried(existing(old), record('claude-code', 'review', responses: %w[r1], sources: ['s2']))
    assert_includes body, 'implementation'
  end

  # Break: records without response IDs fall back to source and interval.
  def test_unknown_responses_compare_source_and_interval
    old = record('codex', 'earlier', responses: [], from: '2026-09-14T10:00:00Z', to: '2026-09-14T11:00:00Z')
    later = record('codex', 'later', responses: [], from: '2026-09-14T12:00:00Z', to: '2026-09-14T13:00:00Z')
    assert_includes carried(existing(old), later), 'earlier'
    overlapping = record('codex', 'overlap', responses: [], from: '2026-09-14T10:30:00Z', to: '2026-09-14T12:00:00Z')
    refute_includes carried(existing(old), overlapping), 'earlier'
    unknown = record('codex', 'unknown', responses: [], from: 'UNKNOWN', to: 'UNKNOWN')
    refute_includes carried(existing(old), unknown), 'earlier'
  end

  # Break: regenerating from an unreadable source replaced measured usage with an empty snapshot.
  def test_measured_report_survives_a_same_source_report_without_responses
    old = record('codex', 'measured', responses: %w[a])
    empty = record('codex', 'empty', responses: [], from: 'UNKNOWN', to: 'UNKNOWN')
    assert_includes carried(existing(old), empty), 'measured'
  end

  # Break: an unrelated new report with response IDs skipped the fallback for an old one without them.
  def test_missing_id_fallback_applies_beside_unrelated_reports
    old = record('codex', 'old', responses: [])
    same_source = record('codex', 'refresh', responses: %w[c1])
    unrelated = record('codex', 'other', responses: %w[b], sources: ['s2'])
    refute_includes carried(existing(old), "#{same_source}\n\n#{unrelated}"), 'old'
  end

  def test_hand_written_usage_keeps_prior_records_without_duplicating_pasted_ones
    old = record('codex', 'codex-review', responses: %w[r1])
    assert_includes carried(existing(old), "| Metric | x |\n| --- | --- |\n| Input | UNKNOWN |"), 'codex-review'
    assert_equal 1, carried(existing(old), "Pasted:\n\n#{old}").scan(Shaka::UsageRecords::END_MARK).size
  end

  # Break: text outside the managed region belongs to someone else and is never adopted.
  def test_only_records_inside_the_managed_region_are_carried
    outside = record('codex', 'outside-region', responses: %w[o1])
    body = carried(existing(outside: "#{outside}\n\n"), record('codex', 'new', responses: %w[n1]))
    refute_includes body, 'outside-region'
  end

  def pull_from(head)
    { 'body' => existing(record('codex', 'forged', responses: %w[f1])), 'head' => { 'repo' => { 'full_name' => head } },
      'base' => { 'repo' => { 'full_name' => 'shakacode/shaka' } } }
  end

  # Break: a fork author could forge a report that the helper then republished as its own evidence.
  def test_reports_from_a_fork_pull_request_are_not_carried
    content, stats = Shaka::UsageRecords.carry_from(described('new'), pull_from('fork/shaka'))
    refute_includes content['details'].first['body'], 'forged'
    assert_equal 'fork', stats['skipped']
  end

  # Break: a fork publish kept a marked block its author supplied as usage.carried.
  def test_a_fork_cannot_supply_its_own_carried_reports
    content = { 'usage' => { 'note' => 'n', 'carried' => record('codex', 'forged', responses: %w[x1]) } }
    carried_content, = Shaka::UsageRecords.carry_from(content, pull_from('fork/shaka'))
    refute carried_content['usage'].key?('carried')
  end

  def test_reports_from_a_same_repository_pull_request_are_carried
    content, = Shaka::UsageRecords.carry_from(described('new'), pull_from('shakacode/shaka'))
    assert_includes content['details'].first['body'], 'forged'
  end

  def test_content_without_a_prior_region_is_unchanged
    content = described('x')
    assert_equal [content, { 'retained' => 0, 'replaced' => 0, 'dropped' => 0 }],
                 Shaka::UsageRecords.carry(content, 'plain body')
  end
end

# Carried reports edited out of the helper's shape are dropped, never adopted.
class UsageRecordsShapeTest < Minitest::Test
  include UsageRecordsFixture

  # Break: a report missing its end marker swallowed the next valid report.
  def test_unterminated_report_is_dropped_without_losing_the_next_one
    cut = record('codex', 'cut', responses: %w[a1]).delete_suffix(Shaka::UsageRecords::END_MARK)
    kept = record('codex', 'kept', responses: %w[k1])
    content, stats = Shaka::UsageRecords.carry(described(record('codex', 'new', responses: %w[n1])),
                                               existing(cut, kept))
    assert_includes content['details'].first['body'], 'kept'
    assert_equal({ 'retained' => 1, 'replaced' => 0, 'dropped' => 1 }, stats)
  end

  # Break: a closing tag before its opener passed the count check and closed the outer disclosure.
  def test_reversed_details_tags_are_dropped
    reversed = record('codex', 'reversed', responses: %w[v1])
               .sub('<details>', '</details>').sub(%r{</details>\n<!--}, "<details>\n<!--")
    refute_includes carried(existing(reversed), record('codex', 'new', responses: %w[n1])), 'reversed'
  end

  # Break: an uppercase closing tag passed the balance check and closed the outer disclosure.
  def test_details_tag_variants_are_dropped
    ['</DETAILS>', '<details open>'].each do |variant|
      odd = record('codex', 'odd', responses: %w[v1]).sub("\n#{Shaka::UsageRecords::END_MARK}",
                                                          "#{variant}\n#{Shaka::UsageRecords::END_MARK}")
      refute_includes carried(existing(odd), record('codex', 'new', responses: %w[n1])), 'odd'
    end
  end

  # Break: a malformed new report replaced valid history, then was itself dropped on the next update.
  def test_malformed_new_report_does_not_replace_history
    old = record('codex', 'history', responses: %w[h1])
    malformed = record('codex', 'malformed', responses: %w[h1]).sub('</details>', '</DETAILS>')
    assert_includes carried(existing(old), malformed), 'history'
  end

  # Break: an edited block could smuggle markers or unbalanced markup under the helper's output.
  def test_blocks_that_lost_the_report_shape_are_dropped_and_counted
    broken = record('codex', 'broken', responses: %w[b1]).sub('</details>', '')
    marked = record('codex', 'marked', responses: %w[m1]).sub('Token detail', '<!-- shaka:reply:x -->')
    unreadable = "<!-- shaka:usage {not json} -->\nx\n#{Shaka::UsageRecords::END_MARK}"
    content, stats = Shaka::UsageRecords.carry(described(record('codex', 'new', responses: %w[n1])),
                                               existing(broken, unreadable).sub('S', "S\n#{marked}"))
    body = content['details'].first['body']
    ['broken', 'marked', 'not json'].each { |text| refute_includes body, text }
    assert_equal({ 'retained' => 0, 'replaced' => 0, 'dropped' => 3 }, stats)
  end

  def test_structured_records_keep_a_disjoint_earlier_report
    old = record('claude-code', 'opus-impl', responses: %w[c1 c2])
    fresh = DEFAULTS.merge('host' => 'codex', 'responses' => %w[x1], 'sources' => ['s2'])
    content = { 'usage' => { 'records' => [fresh] } }
    carried_content, stats = Shaka::UsageRecords.carry(content, existing(old))
    assert_includes carried_content.dig('usage', 'carried'), 'opus-impl'
    assert_equal 1, stats['retained']
  end

  def test_a_later_structured_publish_keeps_the_earlier_table
    table = "| Metric | opus |\n| --- | ---: |\n| USD estimate | $3.269110 |"
    identity = DEFAULTS.merge('host' => 'claude-code', 'responses' => %w[c1])
    old = "#{Shaka::UsageRecords.begin_mark(identity)}\n#{table}\n#{Shaka::UsageRecords::END_MARK}"
    fresh = DEFAULTS.merge('host' => 'codex', 'responses' => %w[x1], 'sources' => ['s2'], 'columns' => [])
    content = { 'usage' => { 'note' => 'n', 'records' => [fresh] } }
    carried_content, stats = Shaka::UsageRecords.carry(content, existing(old))
    assert_includes carried_content.dig('usage', 'carried'), '$3.269110'
    assert_equal 1, stats['retained']
  end

  def test_a_record_that_could_close_the_marker_is_refused
    forged = DEFAULTS.merge('host' => 'codex-->', 'responses' => %w[x1])
    error = assert_raises(Shaka::Error) { Shaka::UsageRecordCarry.identity!(forged) }
    assert_includes error.message, 'identity'
    refute_includes error.message, '-->'
  end

  # Break: an unchecked extra identity field was written into the marker and could close it.
  def test_extra_identity_fields_are_not_kept
    forged = DEFAULTS.merge('host' => 'codex', 'responses' => %w[x1], 'extra' => '--></details>')
    assert_equal forged.except('extra'), Shaka::UsageRecordCarry.identity!(forged)
  end

  def test_caller_supplied_carried_text_is_not_published
    old = record('claude-code', 'opus-impl', responses: %w[c1])
    content = { 'usage' => { 'note' => 'n', 'carried' => 'injected table' } }
    carried_content, = Shaka::UsageRecords.carry(content, existing(old))
    assert_includes carried_content.dig('usage', 'carried'), 'opus-impl'
    refute_includes carried_content.dig('usage', 'carried'), 'injected table'
  end

  def test_a_usage_object_without_records_still_keeps_the_earlier_report
    old = record('claude-code', 'opus-impl', responses: %w[c1])
    content = { 'usage' => { 'note' => 'n', 'columns' => [] } }
    carried_content, = Shaka::UsageRecords.carry(content, existing(old))
    assert_includes carried_content.dig('usage', 'carried'), 'opus-impl'
  end
end

# Only a report that read counters for every selected response may replace measured history.
class UsageRecordsCompletenessTest < Minitest::Test
  include UsageRecordsFixture

  # Break: a record missing its completeness flag was treated as complete and replaced history.
  def test_new_report_without_a_completeness_flag_does_not_replace_history
    old = record('codex', 'measured', responses: %w[a])
    unflagged = record('codex', 'unflagged', responses: %w[a]).sub('"complete":true,', '')
    assert_includes carried(existing(old), unflagged), 'measured'
  end

  # Break: republishing the same incomplete structured record carried its old copy too, doubling the cost.
  def test_the_same_incomplete_record_published_again_replaces_its_copy
    identity = DEFAULTS.merge('host' => 'codex', 'responses' => %w[a], 'complete' => false)
    old = "#{Shaka::UsageRecords.begin_mark(identity)}\n<!-- usage-columns [] -->\n#{Shaka::UsageRecords::END_MARK}"
    content = { 'usage' => { 'note' => 'n', 'records' => [identity.merge('columns' => [])] } }
    carried_content, stats = Shaka::UsageRecords.carry(content, existing(old))
    refute carried_content['usage'].key?('carried')
    assert_equal 1, stats['replaced']
  end

  def test_incomplete_new_report_does_not_replace_measured_history
    old = record('codex', 'measured', responses: %w[a])
    incomplete = record('codex', 'incomplete', responses: %w[a], complete: false)
    assert_includes carried(existing(old), incomplete), 'measured'
  end
end

# A report that read no source must not outlive a report that measured the same work.
class UsageRecordsReadNothingTest < Minitest::Test
  include UsageRecordsFixture

  # Break: PR 307 kept three Cursor reports that read no source beside the Cursor report that measured
  # those commits, because only the new Claude review was compared with them.
  def test_a_report_that_read_nothing_gives_way_to_a_carried_one_that_measured_its_work
    empty = record('cursor', 'read-nothing', sources: [], responses: [], from: 'UNKNOWN', to: 'UNKNOWN')
    measured = record('cursor', 'measured', responses: %w[g1], commits: [COMMIT, 'b' * 40])
    review = record('claude-code', 'review', responses: %w[r1], sources: ['s2'], contribution: 'review')
    content, stats = Shaka::UsageRecords.carry(described(review), existing(empty, measured))
    body = content['details'].first['body']
    refute_includes body, 'read-nothing'
    assert_includes body, 'measured'
    assert_equal({ 'retained' => 1, 'replaced' => 1, 'dropped' => 0 }, stats)
  end

  def test_a_report_that_read_nothing_stays_beside_other_work
    empty = record('cursor', 'read-nothing', sources: [], responses: [], from: 'UNKNOWN', to: 'UNKNOWN')
    other = record('cursor', 'other-commit', responses: %w[g1], commits: ['b' * 40])
    review_of_it = record('cursor', 'review-of-it', responses: %w[g2], contribution: 'review')
    body = carried(existing(empty, other, review_of_it), record('codex', 'new', responses: %w[x1], sources: ['s3']))
    assert_includes body, 'read-nothing'
  end
end
