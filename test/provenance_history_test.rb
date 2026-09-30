# frozen_string_literal: true

require_relative 'publication_test'
require 'shaka/workflow_version'

# Publishes descriptions in sequence, each reading the body the previous one stored.
module ProvenanceHistoryFixture
  REPO = { 'full_name' => 'owner/repo' }.freeze
  HEADS = ('1'..'9').map { |digit| digit * 40 }.freeze

  def setup
    @body = ''
  end

  def workflow(commit = 'a' * 40, modified: false)
    Shaka::WorkflowVersion::Result.new(version: Shaka::VERSION, commit:, modified:, upstream: true)
  end

  def content(usage: PublicationRegressionTest::USAGE_OBJECT, **routes)
    { 'identity' => PublicationRegressionTest::IDENTITY, 'summary' => 'A summary.',
      'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
      'table' => PublicationRegressionTest::TABLE, 'provenance' => PUBLIC_PROVENANCE.merge(routes),
      'usage' => usage, 'details' => [] }
  end

  # Publishes as `shaka description` does: usage carries first, and the next call reads this body.
  def publish(head, version: workflow, fork: false, usage: PublicationRegressionTest::USAGE_OBJECT, **routes)
    pull = pull_for(head, fork:)
    carried, = Shaka::UsageRecords.carry_from(content(usage:, **routes), pull)
    rendered = Shaka::Publication.description(carried, version, pull)
    @body = "<!-- shaka:begin -->\n#{rendered}<!-- shaka:end -->"
    rendered
  end

  def history_rows(rendered)
    history = rendered[%r{<summary>Provenance history</summary>\n\n(.*?)\n\n</details>}m, 1]
    history ? history.lines.map(&:chomp).grep(/\A\| `\h{7}`/) : []
  end

  def pull_for(head, body = @body, fork: false)
    { 'body' => body, 'head' => { 'sha' => head, 'repo' => fork ? { 'full_name' => 'fork/repo' } : REPO },
      'base' => { 'repo' => REPO } }
  end
end

# A PR outlives one helper commit and one route, so each change keeps its own entry.
class ProvenanceHistoryTest < Minitest::Test
  include ProvenanceHistoryFixture

  CHANGED = 'b' * 40
  HIGH = { 'requested_effort' => 'high' }.freeze
  OPUS = HIGH.merge('recommended_model' => 'claude-opus-5-5').freeze
  # Each step changes one compared value from the step before it: [routes, commit, modified, expected].
  STEPS = [
    [{}, 'a' * 40, false, 'gpt-5.6-terra / medium | gpt-5.6-terra / medium | gpt-5.6-terra / medium |'],
    [{}, CHANGED, false, '[`bbbbbbb`]'],
    [{}, CHANGED, true, '(modified)'],
    [HIGH, CHANGED, true, '| gpt-5.6-terra / high |'],
    [OPUS, CHANGED, true, '| claude-opus-5-5 / medium |'],
    [OPUS.merge('active_effort' => 'low'), CHANGED, true, '| gpt-5.6-terra / low |']
  ].freeze

  def test_a_republish_with_unchanged_provenance_adds_no_entry
    publish(HEADS[0])
    rendered = publish(HEADS[1])

    assert_empty history_rows(rendered)
    refute_includes rendered, 'Provenance history'
  end

  def test_each_workflow_or_route_change_adds_one_entry_with_its_head
    STEPS.each_with_index do |(routes, commit, modified), index|
      publish(HEADS[index], version: workflow(commit, modified:), **routes)
    end

    assert_rows(STEPS.zip(HEADS).map { |step, head| [head, step.last] })
  end

  def test_history_survives_a_publication_that_carries_usage
    publish(HEADS[0])
    record = USAGE_RECORD.merge('responses' => ['c2'], 'columns' => [PublicationRegressionTest::USAGE_COLUMN])
    rendered = publish(HEADS[1], usage: { 'note' => 'Later.', 'records' => [record] }, 'active_effort' => 'high')

    assert_equal 2, history_rows(rendered).size
    assert_includes rendered, '"responses":["c1"]'
    assert_includes rendered, '"responses":["c2"]'
  end

  def test_entries_beyond_the_bound_are_omitted_and_the_first_is_kept
    efforts = %w[low high]
    23.times { |index| publish(format('%07x', index).ljust(40, '0'), 'active_effort' => efforts[index % 2]) }
    rows = history_rows(@body)

    assert_equal 21, rows.size
    assert_includes rows.first, '`0000000`'
    assert_includes rows[1], '`0000003`'
    assert_includes @body, '2 entries after the first are omitted.'
  end

  private

  def assert_rows(expected)
    rows = history_rows(@body)
    assert_equal expected.size, rows.size
    rows.zip(expected).each do |row, (head, text)|
      assert row.start_with?("| `#{head[0, 7]}` |"), row
      assert_includes row, text
    end
  end
end

# Only the helper writes the history, so damaged or supplied history publishes nothing.
class ProvenanceHistoryRefusalTest < Minitest::Test
  include ProvenanceHistoryFixture

  def test_a_tampered_or_repeated_history_is_refused
    publish(HEADS[0])
    publish(HEADS[1], 'active_effort' => 'high')
    ['"omitted":0', '"head":"1111', 'gpt-5.6-terra / medium', '"entries":['].each do |target|
      tampered = @body.sub(/(<!-- shaka:provenance .*?)#{Regexp.escape(target)}/) { "#{Regexp.last_match(1)}x" }
      refute_equal @body, tampered, target
      assert_refused(tampered)
    end
    assert_refused(@body.sub('<!-- shaka:end -->', "#{@body[/<!-- shaka:provenance .*? -->/]}\n<!-- shaka:end -->"))
  end

  # Break: a marker split across lines no longer matched, so its history restarted silently.
  def test_a_marker_that_no_longer_parses_as_a_marker_is_refused
    publish(HEADS[0])
    publish(HEADS[1], 'active_effort' => 'high')
    assert_refused(@body.sub('<!-- shaka:provenance ', "<!-- shaka:provenance\n"))
    assert_refused(@body.sub(%r{ -->(?=\n\n</details>\n\n<details>\n<summary>Provenance history)}, ' --'))
  end

  # Every shape the Workflow version cell renders must read back, or the next publication refuses.
  def test_unlinked_and_unknown_workflow_versions_round_trip
    unlinked = Shaka::WorkflowVersion::Result.new(version: Shaka::VERSION, commit: 'd' * 40, modified: true,
                                                  upstream: false)
    unknown = Shaka::WorkflowVersion::Result.new(version: Shaka::VERSION, commit: nil, modified: true, upstream: false)
    [workflow, unlinked, unknown, workflow].each_with_index { |version, index| publish(HEADS[index], version:) }

    assert_equal 4, history_rows(@body).size
    assert_includes @body, "`#{'d' * 40}` (modified)"
    assert_includes @body, "`#{Shaka::VERSION}` (commit unknown, modified)"
  end

  def test_a_fork_body_starts_a_new_history
    publish(HEADS[0])
    rendered = publish(HEADS[1], fork: true, 'active_effort' => 'high')

    refute_includes rendered, 'Provenance history'
    assert_includes rendered, %("head":"#{HEADS[1]}")
    refute_includes rendered, HEADS[0]
  end

  def test_a_supplied_history_details_item_is_refused
    details = [{ 'summary' => 'Provenance history', 'body' => 'rows' }]
    error = assert_raises(Shaka::Error) do
      Shaka::Publication.description(content.merge('details' => details), workflow, pull_for(HEADS[0]))
    end
    assert_includes error.message, 'carried from the PR body'
  end

  private

  def assert_refused(body)
    error = assert_raises(Shaka::Error) do
      Shaka::Publication.description(content, workflow, pull_for(HEADS[2], body))
    end
    assert_includes error.message, 'provenance history'
  end
end
