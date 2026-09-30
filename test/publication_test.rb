# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/publication/publication'

PUBLIC_PROVENANCE = { 'task_source' => 'description', 'initial_prompt' => 'EXCLUDED',
                      'requested_model' => 'gpt-5.6-terra', 'requested_effort' => 'medium',
                      'recommended_model' => 'gpt-5.6-terra', 'recommended_effort' => 'medium',
                      'active_model' => 'gpt-5.6-terra', 'active_effort' => 'medium' }.freeze

# Reproduces the presentation failures observed on real published pull requests.
class PublicationRegressionTest < Minitest::Test
  IDENTITY = { 'agent' => 'Codex', 'provider' => 'OpenAI', 'model' => 'gpt-5.6-terra', 'effort' => 'low' }.freeze
  TABLE = { 'columns' => %w[Check Commit Result], 'rows' => [%w[bin/validate abc123 pass]] }.freeze
  USAGE = { 'summary' => 'Usage',
            'body' => "| Provider | Native total |\n| --- | ---: |\n| openai | 1 |" }.freeze
  USAGE_COLUMN = {
    'label' => 'openai', 'provider' => 'openai', 'model' => 'gpt-test', 'routed' => 'UNKNOWN',
    'effort' => 'high', 'credits' => 'UNKNOWN', 'usd' => 'UNKNOWN', 'input' => '1',
    'cached_input' => '0', 'output' => '0', 'reasoning_output' => 'UNKNOWN', 'cache_writes' => 'UNKNOWN'
  }.freeze
  USAGE_OBJECT = { 'note' => 'Native usage is PARTIAL.',
                   'records' => [USAGE_RECORD.merge('columns' => [USAGE_COLUMN])] }.freeze
  WALKTHROUGH = 'https://github.com/shakacode/shaka/pull/137#pullrequestreview-5258565629'

  def description_content(**changes)
    { 'identity' => IDENTITY, 'summary' => 'A summary.', 'walkthrough' => WALKTHROUGH, 'table' => TABLE,
      'deployment' => 'none', 'provenance' => PUBLIC_PROVENANCE, 'usage' => USAGE_OBJECT,
      'details' => [] }.merge(changes)
  end

  # https://github.com/shakacode/shaka/pull/37 published its whole description as one
  # line containing literal backslash-n sequences instead of paragraph breaks.
  def test_escaped_newlines_in_supplied_text_are_reported_before_publication
    content = description_content(
      'summary' => 'Resolves #34 with post-rename maintenance.\n\n## Validation\n\nbin/validate passed.'
    )
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(content) }
    assert_includes error.message, 'escape sequence'
  end

  def test_real_newlines_and_unicode_and_code_escapes_are_preserved
    body = "First line.\n\nSecond café 🤖 line.\n\n```ruby\nputs \"a\\nb\"\n```\n\nUse `\\n` to separate."
    rendered = Shaka::Publication.description(
      description_content('sections' => [{ 'heading' => 'Detail', 'body' => body }])
    )
    assert_includes rendered, 'Second café 🤖 line.'
    assert_includes rendered, 'puts "a\nb"'
    assert_includes rendered, 'Use `\n` to separate.'
  end

  # https://github.com/shakacode/shaka/pull/38 published a ten-column usage table with an
  # eleven-column separator, so GitHub rendered zero tables and showed the pipes as text.
  def test_table_separator_always_matches_the_column_count
    columns = %w[Provider Model Routed Effort Input Cached Output Reasoning Writes Total]
    rendered = Shaka::Publication.description(
      description_content('table' => { 'columns' => columns, 'rows' => [%w[openai sol UNKNOWN medium 1 2 3 4 5 6]] })
    )
    widths = visible_table_widths(rendered)
    assert_equal [columns.size] * 3, widths
  end

  def visible_table_widths(markdown)
    markdown.split('<details>', 2).first.lines.select { |line| line.start_with?('|') }.map do |line|
      line.strip.delete_prefix('|').delete_suffix('|').split('|').size
    end
  end

  def test_row_width_mismatch_is_a_focused_diagnostic_not_a_broken_table
    content = description_content('table' => { 'columns' => %w[A B C], 'rows' => [%w[1 2]] })
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(content) }
    assert_includes error.message, '3'
    assert_includes error.message, '2'
  end

  # https://github.com/shakacode/shaka/pull/71 published validation and usage as prose,
  # so GitHub rendered no tables in the managed description.
  def test_a_description_without_a_table_is_refused
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(description_content.except('table')) }
    assert_includes error.message, 'table'
  end

  def test_usage_details_restated_as_prose_are_refused
    prose = { 'summary' => 'Final native usage snapshot',
              'body' => 'Native usage is PARTIAL: 70 responses from the latest Codex turn.' }
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(description_content('details' => [prose])) }
    assert_includes error.message, 'usage'
  end

  def test_a_separator_line_alone_does_not_count_as_a_usage_table
    decoy = { 'summary' => 'Usage',
              'body' => "Native usage is PARTIAL: 70 responses.\n\n| --- |" }
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(description_content('details' => [decoy])) }
    assert_includes error.message, 'usage'
  end

  def test_a_later_usage_detail_with_a_complete_table_is_refused
    error = assert_raises(Shaka::Error) do
      Shaka::Publication.description(
        description_content('details' => [
                              { 'summary' => 'Usage notes', 'body' => 'See the snapshot below.' },
                              USAGE
                            ])
      )
    end
    assert_includes error.message, 'usage object'
  end
end

# Structure the renderer owns so models cannot vary it.
class PublicationStructureTest < Minitest::Test
  IDENTITY = PublicationRegressionTest::IDENTITY

  def render(**changes)
    Shaka::Publication.description(
      { 'identity' => IDENTITY, 'summary' => 'A summary.',
        'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
        'table' => PublicationRegressionTest::TABLE,
        'provenance' => PUBLIC_PROVENANCE,
        'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }.merge(changes)
    )
  end

  def test_identity_line_leads_the_description
    assert_match(/\A🤖 Codex · OpenAI · gpt-5\.6-terra · low\n\nA summary\.\n/, render)
  end

  def test_sections_become_second_level_headings_separated_by_one_blank_line
    rendered = render('sections' => [{ 'heading' => 'Purpose', 'body' => 'Why.' },
                                     { 'heading' => 'Validation', 'body' => 'How.' }])
    assert_includes rendered, "\n## Purpose\n\nWhy.\n\n## Validation\n\nHow.\n"
    refute_includes rendered, "\n\n\n"
  end

  def test_details_keep_the_blank_lines_github_needs_to_render_their_content
    rendered = render('details' => [{ 'summary' => 'Rollback', 'body' => "| A |\n| --- |\n| 1 |" }])
    assert_includes rendered, "<details>\n<summary>Rollback</summary>\n\n| A |"
    assert_includes rendered, "| 1 |\n\n</details>"
  end

  def test_missing_or_empty_required_content_is_reported_before_publication
    [{ 'identity' => IDENTITY }, { 'identity' => IDENTITY, 'summary' => '   ' }, { 'summary' => 'A summary.' }]
      .each { |content| assert_raises(Shaka::Error) { Shaka::Publication.description(content) } }
    assert_raises(Shaka::Error) { render('sections' => [{ 'heading' => '', 'body' => 'Why.' }]) }
    error = assert_raises(Shaka::Error) { render('usage' => nil) }
    assert_includes error.message, 'usage'
  end

  def test_short_replies_stay_short
    rendered = Shaka::Publication.comment({ 'identity' => IDENTITY, 'summary' => 'Fixed in 0a1b2c3.' })
    assert_equal "🤖 Codex · OpenAI · gpt-5.6-terra · low\n\nFixed in 0a1b2c3.\n", rendered
  end

  def test_unknown_identity_fields_are_marked_rather_than_invented
    rendered = Shaka::Publication.comment({ 'identity' => { 'agent' => 'Codex', 'provider' => 'OpenAI' },
                                            'summary' => 'Done.' })
    assert_includes rendered, '🤖 Codex · OpenAI · UNKNOWN · UNKNOWN'
  end

  def test_walkthroughs_carry_their_revision_and_are_not_approvals
    rendered = Shaka::Publication.walkthrough({ 'identity' => IDENTITY, 'summary' => 'What changed.',
                                                'head' => 'a' * 40 })
    assert_includes rendered, 'a' * 40
    assert_includes rendered, 'not an approval'
  end

  # Without this H1, GitHub reviews read as untitled comments instead of the
  # titled COMMENT walkthrough on https://github.com/shakacode/shaka/pull/71#pullrequestreview-5229855190
  def test_walkthroughs_use_an_h1_title_after_identity
    rendered = Shaka::Publication.walkthrough({ 'identity' => IDENTITY, 'summary' => 'What changed.',
                                                'head' => 'a' * 40 })
    assert_match(/\A🤖 Codex · OpenAI · gpt-5\.6-terra · low\n\n# Code Walkthrough\n\nWhat changed.\n/m,
                 rendered)
    refute_includes Shaka::Publication.comment({ 'identity' => IDENTITY, 'summary' => 'Fixed.' }),
                    '# Code Walkthrough'
  end

  def test_a_real_newline_in_a_cell_cannot_split_the_row
    content = { 'identity' => IDENTITY, 'summary' => 'A summary.',
                'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
                'table' => { 'columns' => %w[A B], 'rows' => [%W[one\ntwo three]] },
                'provenance' => PUBLIC_PROVENANCE }
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(content) }
    assert_includes error.message, 'single line'
  end

  def test_a_real_newline_in_a_heading_column_or_details_summary_is_refused
    [{ 'sections' => [{ 'heading' => "A\nB", 'body' => 'Why.' }] },
     { 'table' => { 'columns' => ["A\nB"], 'rows' => [] } },
     { 'details' => [{ 'summary' => "A\nB", 'body' => 'Why.' }] }].each do |part|
      assert_raises(Shaka::Error) { render(**part) }
    end
  end

  def test_tilde_fences_and_multi_backtick_spans_count_as_code
    body = "~~~\nliteral \\n here\n~~~\n\nand ``a \\n b`` inline."
    rendered = render('sections' => [{ 'heading' => 'Detail', 'body' => body }])
    assert_includes rendered, 'literal \n here'
  end

  # https://github.com/shakacode/shaka/issues/56 — a longer delimiter is how GFM
  # puts a shorter backtick run inside an inline span.
  def test_a_multi_backtick_span_may_contain_a_shorter_backtick_run
    body = 'Use ``a `b` \n c`` inline.'
    rendered = render('sections' => [{ 'heading' => 'Detail', 'body' => body }])
    assert_includes rendered, 'Use ``a `b` \n c`` inline.'
  end

  def test_a_details_summary_cannot_close_its_own_disclosure
    rendered = render('details' => [{ 'summary' => 'Docs for </summary></details> handling', 'body' => 'b' }])
    assert_includes rendered, '<summary>Docs for &lt;/summary&gt;&lt;/details&gt; handling</summary>'
    # Provenance, usage with its glossary and pricing notes, and the supplied details.
    assert_equal 5, rendered.scan('</summary>').size
    assert_equal 5, rendered.scan('</details>').size
  end

  def test_collections_that_are_not_lists_are_refused_rather_than_crashing
    [{ 'sections' => { 'heading' => 'h' } }, { 'sections' => 42 }, { 'details' => 'text' },
     { 'table' => { 'columns' => 'A', 'rows' => [] } },
     { 'table' => { 'columns' => %w[A], 'rows' => 'nope' } }].each do |part|
      error = assert_raises(Shaka::Error) { render(**part) }
      assert_includes error.message, 'list'
    end
  end
end

# https://github.com/shakacode/shaka/pull/137 buried the walkthrough in the opening
# sentence. Keep a dedicated link after the summary instead of a heading that
# repeats the same words as the link text.
class PublicationWalkthroughLinkTest < Minitest::Test
  def render(walkthrough: PublicationRegressionTest::WALKTHROUGH)
    Shaka::Publication.description(
      { 'identity' => PublicationRegressionTest::IDENTITY, 'summary' => 'A summary.',
        'walkthrough' => walkthrough, 'deployment' => 'none', 'table' => PublicationRegressionTest::TABLE,
        'provenance' => PUBLIC_PROVENANCE, 'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }
    )
  end

  def test_descriptions_lead_with_a_code_walkthrough_review_link
    link = PublicationRegressionTest::WALKTHROUGH
    rendered = render

    assert_includes rendered, "A summary.\n\n[Code Walkthrough](#{link})\n"
    refute_includes rendered, '## Code Walkthrough'
    refute_match(/^# Code Walkthrough/, rendered)
  end

  def test_the_walkthrough_link_precedes_other_description_sections
    rendered = render_with_section
    walkthrough_at = rendered.index('[Code Walkthrough](')
    section_at = rendered.index("## Outcome\n")

    refute_nil walkthrough_at
    refute_nil section_at
    assert_operator walkthrough_at, :<, section_at
  end

  def render_with_section
    Shaka::Publication.description(
      { 'identity' => PublicationRegressionTest::IDENTITY, 'summary' => 'A summary.',
        'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
        'sections' => [{ 'heading' => 'Outcome', 'body' => 'What landed.' }],
        'table' => PublicationRegressionTest::TABLE, 'provenance' => PUBLIC_PROVENANCE,
        'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }
    )
  end

  def test_a_description_without_a_walkthrough_link_reserves_the_placeholder
    rendered = render(walkthrough: nil)

    assert_includes rendered, "A summary.\n\n_Not published yet._"
    refute_includes rendered, '[Code Walkthrough]('
    refute_includes rendered, '## Code Walkthrough'
  end

  def test_a_blank_walkthrough_link_reserves_the_placeholder
    rendered = render(walkthrough: '  ')

    assert_includes rendered, "A summary.\n\n_Not published yet._"
    refute_includes rendered, '[Code Walkthrough]('
    refute_includes rendered, '## Code Walkthrough'
  end

  def test_a_blob_pr_or_issue_comment_url_is_not_a_walkthrough_link
    %w[
      https://github.com/shakacode/shaka/blob/abc/README.md
      https://github.com/shakacode/shaka/pull/137
      https://github.com/shakacode/shaka/pull/137#issuecomment-5746446012
    ].each do |url|
      error = assert_raises(Shaka::Error) { render(walkthrough: url) }
      assert_includes error.message, 'walkthrough'
    end
  end
end

class PublicationProvenanceRequirementTest < Minitest::Test
  # Catches a renderer that accepts the structured metadata but silently drops it,
  # leaving a PR without the route evidence needed for later comparison.
  def test_description_renders_public_safe_execution_provenance
    content = { 'identity' => PublicationStructureTest::IDENTITY, 'summary' => 'A summary.',
                'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
                'table' => PublicationRegressionTest::TABLE, 'provenance' => PUBLIC_PROVENANCE,
                'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }
    rendered = Shaka::Publication.description(content)

    assert_includes rendered, '<summary>Execution provenance</summary>'
    assert_includes rendered, '| Machine alias |'
    assert_includes rendered, '| Requested route | gpt-5.6-terra / medium |'
    refute_includes rendered, '| Initial prompt |'
    refute_includes rendered, '| Observed route |'
  end

  def test_description_refuses_missing_execution_provenance
    content = { 'identity' => PublicationStructureTest::IDENTITY, 'summary' => 'A summary.',
                'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
                'table' => PublicationRegressionTest::TABLE,
                'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }
    error = assert_raises(Shaka::Error) { Shaka::Publication.description(content) }

    assert_includes error.message, 'provenance'
  end
end

# https://github.com/shakacode/shaka-shakacode-com/pull/3 left out the live preview that
# https://github.com/shakacode/shaka-shakacode-com/pull/2 wrote into its summary, so the
# renderer places the deployment link beside the walkthrough link and requires a choice.
class PublicationDeploymentLinkTest < Minitest::Test
  DEPLOYMENT = 'https://shaka-shakacode-com.justin-fed.workers.dev'

  def render(**changes)
    Shaka::Publication.description(
      { 'identity' => PublicationRegressionTest::IDENTITY, 'summary' => 'A summary.',
        'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => DEPLOYMENT,
        'sections' => [{ 'heading' => 'Outcome', 'body' => 'What landed.' }],
        'table' => PublicationRegressionTest::TABLE, 'provenance' => PUBLIC_PROVENANCE,
        'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }.merge(changes)
    )
  end

  def test_the_deployment_link_follows_the_walkthrough_link_before_any_section
    link = PublicationRegressionTest::WALKTHROUGH
    assert_includes render, "A summary.\n\n[Code Walkthrough](#{link}) · [Deployment](<#{DEPLOYMENT}>)\n\n## Outcome"
  end

  def test_the_deployment_link_stays_near_the_top_before_the_walkthrough_exists
    assert_includes render('walkthrough' => nil),
                    "A summary.\n\n_Not published yet._\n\n[Deployment](<#{DEPLOYMENT}>)\n"
  end

  # A bare `)` would end the Markdown link at `/a` instead of linking `/a)b`.
  def test_a_parenthesis_in_the_deployment_url_stays_inside_the_link
    assert_includes render('deployment' => 'https://preview.example/a)b'), '[Deployment](<https://preview.example/a)b>)'
  end

  def test_none_records_that_the_repository_has_no_deployment
    rendered = render('deployment' => 'none')
    refute_includes rendered, 'Deployment'
    assert_includes rendered, "[Code Walkthrough](#{PublicationRegressionTest::WALKTHROUGH})\n\n## Outcome"
  end

  def test_a_missing_or_blank_deployment_is_refused
    [nil, '  '].each do |value|
      error = assert_raises(Shaka::Error) { render('deployment' => value) }
      assert_includes error.message, 'deployment'
    end
  end

  def test_a_deployment_must_be_an_https_url
    ['http://example.com', 'example.com', 'https://example.com/a b', "https://example.com\nx",
     'https://?', 'https://example.com/<x>', 'https://user:secret@preview.example'].each do |value|
      error = assert_raises(Shaka::Error) { render('deployment' => value) }
      assert_includes error.message, 'deployment'
    end
  end
end

# Hosts published WIP Details as prose paragraphs, a table, or unseparated lines
# (https://github.com/shakacode/shaka/pull/258, /pull/254, /pull/248); the helper now owns one table.
class PublicationWipDetailsTest < Minitest::Test
  WIP = { 'owner' => 'm5 · Claude Code · k7q2', 'task' => 'shaka #255 use the tracker branch name',
          'thread' => 'UNKNOWN', 'last_observed_activity' => '2026-09-25 13:31 HST',
          'revision' => 'feature @ 4602d275a094fa555eba472d39b8bca340d7afeb', 'workspace' => 'UNKNOWN',
          'unfinished_work' => 'none', 'stopped_because' => 'paused', 'merge_authority' => 'ask',
          'state' => 'awaiting hosted checks', 'next_action' => 'read claude-review' }.freeze

  def render(wip, details: [])
    content = PublicationRegressionTest.new('render').description_content('wip' => wip, 'details' => details)
    Shaka::Publication.description(content)
  end

  def test_wip_renders_every_field_as_one_table_in_workflow_order
    rendered = render(WIP)
    note = rendered[%r{<details>\n<summary>WIP Details</summary>\n\n(.*?)\n\n</details>}m, 1]
    lines = note.lines.map(&:chomp)
    assert_equal ['| Field | Value |', '| --- | --- |'], lines.first(2)
    labels = lines.drop(2).map { |line| line.split(' | ').first.delete_prefix('| ') }
    assert_equal Shaka::WipDetails::FIELDS.values, labels
    assert_includes lines, '| Stopped because | paused |'
  end

  def test_wip_follows_the_usage_details
    rendered = render(WIP)
    assert_operator rendered.index('<summary>Usage'), :<, rendered.index('<summary>WIP Details')
  end

  def test_the_note_is_omitted_after_the_outcome
    refute_includes render(nil), 'WIP Details'
  end

  def test_a_pipe_in_a_value_stays_inside_its_cell
    assert_includes render(WIP.merge('state' => 'a | b')), '| State | a \\| b |'
  end

  def test_a_backslash_before_a_pipe_cannot_undo_its_escape
    assert_includes render(WIP.merge('state' => 'a\\|b')), '| State | a\\\\\\|b |'
  end

  def test_missing_and_unknown_fields_are_named
    error = assert_raises(Shaka::Error) { render(WIP.except('thread')) }
    assert_includes error.message, 'missing fields: thread'
    error = assert_raises(Shaka::Error) { render(WIP.merge('mood' => 'fine')) }
    assert_includes error.message, 'unknown fields: mood'
  end

  def test_blank_and_multiline_values_are_refused
    ['', "two\nlines", 7].each do |value|
      error = assert_raises(Shaka::Error) { render(WIP.merge('task' => value)) }
      assert_includes error.message, 'wip task'
    end
  end

  def test_a_hand_written_wip_details_item_is_refused
    prose = { 'summary' => 'WIP Details', 'body' => "Owner: m5\nTask: something" }
    error = assert_raises(Shaka::Error) { render(nil, details: [prose]) }
    assert_includes error.message, 'wip object'
  end
end

# Hosts each wrote a different usage table (#258, #254, #248). Ruby renders one.
class PublicationUsageTableTest < Minitest::Test
  COLUMN = {
    'label' => 'claude-opus-5-5 implementation', 'provider' => 'anthropic', 'model' => 'claude-opus-5-5',
    'routed' => 'claude-opus-5-5', 'effort' => 'medium', 'credits' => 'UNKNOWN', 'usd' => '$3.269110',
    'input' => '100', 'cached_input' => '7558810', 'output' => '27535', 'reasoning_output' => '7687',
    'cache_writes' => '150781'
  }.freeze
  REVIEW = COLUMN.merge('label' => 'claude-opus-5-5 review', 'usd' => '$0.308079', 'input' => '6',
                        'cached_input' => '96593', 'output' => 'UNKNOWN', 'reasoning_output' => 'UNKNOWN',
                        'cache_writes' => 'UNKNOWN').freeze

  def self.usage_of(*columns, note: 'n') = { 'note' => note, 'records' => [USAGE_RECORD.merge('columns' => columns)] }

  def usage_of(*columns) = self.class.usage_of(*columns)

  def render(usage: self.class.usage_of(COLUMN, REVIEW, note: 'Native usage is PARTIAL.'), details: [])
    Shaka::Publication.description(
      PublicationRegressionTest.new('render').description_content('usage' => usage, 'details' => details)
    )
  end

  RENDERED = <<~TABLE.chomp
    | Report | USD | Input | Cached input | Output | Reasoning | Cache writes |
    | --- | ---: | ---: | ---: | ---: | ---: | ---: |
    | claude‑opus‑5‑5 implementation | $3.27 | 100 | 7.6M | 27.5K | 7.7K | 151K |
    | claude‑opus‑5‑5 review | $0.31 | 6 | 96.6K | — | — | — |
    | **Total** | $3.58 |  |  |  |  |  |
  TABLE

  # Break: PR 307 published one column per report, so nine reports scrolled sideways,
  # and the summary listed every estimate instead of what the PR cost.
  def test_renders_one_row_per_report_with_a_total
    rendered = render
    assert_includes rendered, RENDERED
    assert_includes rendered, '<summary>Usage and cost · $3.58 estimated</summary>'
    assert_includes rendered, '_— not reported._'
    assert_operator rendered.index('| Report |'), :<, rendered.index('Native usage is PARTIAL.')
  end

  # Break: a Credits row of UNKNOWN in every column told the reader nothing.
  def test_a_metric_no_report_measured_is_left_out
    refute_includes render, 'Credits'
    credited = render(usage: usage_of(COLUMN.merge('credits' => '1.500000')))
    assert_includes credited, '| Report | USD | Codex credits |'
    assert_includes credited, '| $3.27 | 1.50 |'
  end

  # Break: the total row's blank token cells brought back columns no report measured.
  def test_a_total_row_does_not_bring_back_unmeasured_columns
    other = REVIEW.merge('label' => 'other review')
    refute_includes render(usage: usage_of(REVIEW, other)), 'Reasoning'
  end

  def test_amounts_show_cents_and_partial_estimates_are_minimums
    tiny = COLUMN.merge('usd' => '$0.000412')
    assert_includes render(usage: usage_of(tiny)), '| <$0.01 |'
    partial = COLUMN.merge('usd' => '$1234.5 (partial)')
    rendered = render(usage: usage_of(partial))
    assert_includes rendered, '| $1,234.50+ |'
    assert_includes rendered, '<summary>Usage and cost · $1,234.50+ estimated</summary>'
  end

  def test_no_estimate_leaves_the_summary_plain
    unknown = COLUMN.merge('usd' => 'UNKNOWN')
    assert_includes render(usage: usage_of(unknown)), '<summary>Usage and cost</summary>'
  end

  def test_a_missing_column_metric_is_named
    error = assert_raises(Shaka::Error) { render(usage: usage_of(COLUMN.except('output'))) }
    assert_includes error.message, 'output'
  end

  def test_a_column_that_could_close_a_comment_is_refused
    ['usd--> <img>', 'x--!>'].each do |forged|
      error = assert_raises(Shaka::Error) do
        render(usage: usage_of(COLUMN.merge('usd' => forged)))
      end
      assert_includes error.message, 'must not close a comment'
      refute_includes error.message, forged
    end
  end

  # Break: a table published without records had nothing a later publish could carry.
  def test_usage_without_recoverable_records_is_refused
    [{ 'note' => 'n' }, { 'note' => 'n', 'records' => [] }].each do |usage|
      assert_includes assert_raises(Shaka::Error) { render(usage:) }.message, 'records'
    end
    bare = { 'note' => 'n', 'records' => [USAGE_RECORD] }
    assert_includes assert_raises(Shaka::Error) { render(usage: bare) }.message, 'columns'
  end

  def test_an_unknown_column_field_is_named
    error = assert_raises(Shaka::Error) do
      render(usage: usage_of(COLUMN.merge('native_total' => '1')))
    end
    assert_includes error.message, 'native_total'
  end

  def test_a_pipe_in_a_label_stays_inside_its_cell
    rendered = render(usage: usage_of(COLUMN.merge('label' => 'a | b')))
    assert_includes rendered, '| a \\| b |'
  end

  def test_a_hand_written_usage_details_item_is_refused
    prose = { 'summary' => 'Usage and cost', 'body' => "| Metric | x |\n| --- | ---: |\n| USD estimate | $1 |" }
    error = assert_raises(Shaka::Error) { render(details: [prose]) }
    assert_includes error.message, 'usage object'
  end
end

# Reports share a row only when they count the same thing the same way.
class PublicationUsageRowGroupingTest < Minitest::Test
  COLUMN = PublicationUsageTableTest::COLUMN
  REVIEW = PublicationUsageTableTest::REVIEW

  def render(usage:) = PublicationUsageTableTest.new('render').render(usage:)
  def usage_of(*columns) = PublicationUsageTableTest.usage_of(*columns)

  # Break: a Codex and a Pi report on one route added input counters that mean different things.
  def test_reports_from_different_hosts_keep_separate_rows
    usage = { 'note' => 'n', 'records' => [USAGE_RECORD.merge('columns' => [REVIEW]),
                                           USAGE_RECORD.merge('host' => 'pi', 'columns' => [REVIEW])] }
    rendered = render(usage:)
    assert_includes rendered, '| claude‑opus‑5‑5 review (claude‑code anthropic claude‑opus‑5‑5 medium) | $0.31 |'
    assert_includes rendered, '| claude‑opus‑5‑5 review (pi anthropic claude‑opus‑5‑5 medium) | $0.31 |'
  end

  # Break: eight review runs of one model became eight columns labeled review through review-8.
  def test_reports_with_one_label_share_a_row
    rendered = render(usage: usage_of(REVIEW, REVIEW.merge('usd' => '$0.001')))
    assert_includes rendered, "| Report | USD | Input | Cached input |\n| --- | ---: | ---: | ---: |\n" \
                              '| claude‑opus‑5‑5 review ×2 | $0.31 | 12 | 193K |'
    refute_includes rendered, '**Total**'
    refute_includes rendered, 'not reported, so'
  end

  # Break: two models whose reports both chose the label `high review` shared one row.
  def test_one_label_on_different_models_keeps_separate_rows
    other = REVIEW.merge('model' => 'gpt-6-astra', 'routed' => 'UNKNOWN', 'effort' => 'high')
    rendered = render(usage: usage_of(REVIEW, other))
    assert_includes rendered, '| claude‑opus‑5‑5 review (claude‑code anthropic claude‑opus‑5‑5 medium) |'
    assert_includes rendered, '| claude‑opus‑5‑5 review (claude‑code anthropic gpt‑6‑astra high) |'
  end
end

# A reader new to these reports can read the table without guessing.
class PublicationUsageReadabilityTest < Minitest::Test
  COLUMN = PublicationUsageTableTest::COLUMN

  def render(usage:) = PublicationUsageTableTest.new('render').render(usage:)
  def usage_of(*columns) = PublicationUsageTableTest.usage_of(*columns)

  # Break: GitHub wrapped claude-opus-5-5 at each hyphen in a narrow Report column.
  def test_report_labels_do_not_break_at_hyphens
    rendered = render(usage: usage_of(COLUMN))
    assert_includes rendered, "| claude\u2011opus\u20115\u20115 implementation |"
    assert_includes rendered, '"label":"claude-opus-5-5 implementation"'
  end

  # Break: 45,332,615-token cells widened the table past the page on desktop.
  def test_token_counts_are_compact
    shown = [999, 1000, 1500, 99_960, 639_114, 999_999, 45_332_615].map { |n| Shaka::UsageNumbers.compact(n) }
    assert_equal %w[999 1K 1.5K 100K 639K 1M 45.3M], shown
  end

  # Break: the maintainer could not tell what the Credits column counted.
  def test_the_glossary_explains_only_the_columns_shown
    rendered = render(usage: usage_of(COLUMN.merge('credits' => '2.000000')))
    glossary = rendered[%r{<summary>What the columns mean</summary>(.*?)</details>}m, 1]
    assert_includes glossary, '**Codex credits**: estimated OpenAI Codex plan credits'
    assert_includes glossary, '**Cache writes**'
    refute_includes render(usage: usage_of(COLUMN)), '**Codex credits**'
    assert_includes glossary, 'OpenCode does not'
  end
end

# Each estimate keeps the rate card that priced it, even after the PR changes hands.
class PublicationUsagePricingTest < Minitest::Test
  COLUMN = PublicationUsageTableTest::COLUMN
  REVIEW = PublicationUsageTableTest::REVIEW
  CURSOR = "Rate card: installed Shaka.\n\nCursor on-demand list prices, verified 2026-09-21.\n\n" \
           'Subagent usage is excluded.'
  ANTHROPIC = "Rate card: installed Shaka.\n\nAnthropic API list prices, verified 2026-09-23."

  def render(usage:) = PublicationUsageTableTest.new('render').render(usage:)

  def record(column, note: ANTHROPIC, **fields) = USAGE_RECORD.merge('columns' => [column], 'note' => note, **fields)

  def pricing(rendered)
    rendered[%r{<summary>How each report was measured and priced</summary>\n\n(.*?)\n\n</details>}m, 1]
  end

  def test_each_note_lists_the_reports_it_priced
    grok = COLUMN.merge('label' => 'grok-4.7 implementation')
    usage = { 'note' => 'n',
              'records' => [record(grok, note: CURSOR, 'host' => 'cursor'), record(REVIEW),
                            record(REVIEW, 'responses' => ['c2'])] }
    notes = pricing(render(usage:))
    assert_includes notes, "**grok\u20114.7 implementation**\n\n#{CURSOR}"
    assert_includes notes, "**claude\u2011opus\u20115\u20115 review ×2**\n\n#{ANTHROPIC}"
  end

  # Break: a later publish showed a carried row beside another report's rate card.
  def test_a_carried_note_survives_the_next_publish
    first = render(usage: { 'note' => 'n', 'records' => [record(COLUMN, note: CURSOR)] })
    block = first[/<!-- shaka:usage .*?<!-- shaka:usage:end -->/m]
    later = render(usage: { 'note' => 'n', 'records' => [record(REVIEW, 'host' => 'codex')] }.merge('carried' => block))
    notes = pricing(later)
    assert_includes notes, "**claude\u2011opus\u20115\u20115 implementation**\n\n#{CURSOR}"
    assert_includes notes, "**claude\u2011opus\u20115\u20115 review**\n\n#{ANTHROPIC}"
  end

  def test_a_report_without_a_note_is_named
    notes = pricing(render(usage: { 'note' => 'n', 'records' => [record(COLUMN, note: nil)] }))
    assert_includes notes, 'No note was recorded for claude'
  end

  def test_a_note_that_could_close_its_comment_is_refused
    usage = { 'note' => 'n', 'records' => [record(COLUMN, note: 'prices --> <img>')] }
    error = assert_raises(Shaka::Error) { render(usage:) }
    assert_includes error.message, 'must not close a comment'
  end
end

# Values from records and carried blocks cannot change the description's structure or totals.
class PublicationUsageSafetyTest < Minitest::Test
  COLUMN = PublicationUsageTableTest::COLUMN

  def render(usage:) = PublicationUsageTableTest.new('render').render(usage:)
  def usage_of(*columns) = PublicationUsageTableTest.usage_of(*columns)

  # Break: a label or note holding </details> closed the usage disclosure, and its raw copy in the
  # hidden record failed the carry shape check on the next publish, dropping the report.
  def test_angle_brackets_in_labels_and_notes_are_refused
    label = USAGE_RECORD.merge('columns' => [COLUMN.merge('label' => 'x </details> y')])
    note = USAGE_RECORD.merge('columns' => [COLUMN], 'note' => 'a </details> b')
    [label, note].each do |record|
      error = assert_raises(Shaka::Error) { render(usage: { 'note' => 'n', 'records' => [record] }) }
      assert_includes error.message, 'must not contain < or >'
    end
  end

  # Break: the top-level usage note skipped the checks a record note gets.
  def test_the_top_level_note_is_checked_like_a_record_note
    ['a </details> b', 'a --> b'].each do |note|
      assert_raises(Shaka::Error) { render(usage: usage_of(COLUMN).merge('note' => note)) }
    end
  end

  # Break: a record copied twice into usage.records, even with a different note, doubled its cost.
  def test_a_record_listed_twice_counts_once
    record = USAGE_RECORD.merge('columns' => [COLUMN])
    repriced = record.merge('note' => 'Rate card: a later one.')
    rendered = render(usage: { 'note' => 'n', 'records' => [record, repriced] })
    assert_includes rendered, '<summary>Usage and cost · $3.27 estimated</summary>'
    refute_includes rendered, '×2'
  end

  # Break: with one row and earlier reports below, the summary showed + but the table did not.
  def test_one_row_with_earlier_reports_gets_a_minimum_total
    legacy = "#{Shaka::UsageRecords.begin_mark(USAGE_RECORD)}\n| Metric | codex |\n| --- | --- |\n" \
             "| USD estimate | $1.000000 |\n#{Shaka::UsageRecords::END_MARK}"
    rendered = render(usage: usage_of(COLUMN).merge('carried' => legacy))
    assert_includes rendered, '| **Total** | $3.27+ |'
  end
end

# Records keep their columns hidden so a later publish can rebuild the one table.
class PublicationUsageRecordTableTest < Minitest::Test
  COLUMN = PublicationUsageTableTest::COLUMN
  REVIEW = PublicationUsageTableTest::REVIEW
  RENDERED = PublicationUsageTableTest::RENDERED

  def render(usage:) = PublicationUsageTableTest.new('render').render(usage:)
  def usage_of(*columns) = PublicationUsageTableTest.usage_of(*columns)

  def test_a_record_block_keeps_that_reports_columns_hidden
    rendered = render(usage: usage_of(COLUMN))
    block = rendered[/<!-- shaka:usage .*?<!-- shaka:usage:end -->/m]
    assert_includes block, '<!-- usage-columns [{"label":"claude-opus-5-5 implementation"'
    assert_includes block, '"usd":"$3.269110"'
    assert_equal 1, rendered.scan('| claude‑opus‑5‑5 implementation |').size
  end

  # Break: carried reports were shown as a second table under the first.
  def test_carried_record_columns_join_the_one_table
    hidden = "<!-- usage-columns #{JSON.generate([REVIEW])} -->"
    block = "#{Shaka::UsageRecords.begin_mark(USAGE_RECORD)}\n#{hidden}\n#{Shaka::UsageRecords::END_MARK}"
    rendered = render(usage: usage_of(COLUMN).merge('carried' => block))
    assert_includes rendered, RENDERED
    assert_includes rendered, block
  end

  def test_a_report_from_before_the_table_stays_visible_below_it
    legacy = "#{Shaka::UsageRecords.begin_mark(USAGE_RECORD)}\n| Metric | codex |\n| --- | --- |\n" \
             "| USD estimate | $1.000000 |\n#{Shaka::UsageRecords::END_MARK}"
    rendered = render(usage: usage_of(COLUMN, REVIEW).merge('carried' => legacy))
    assert_operator rendered.index('| Report |'), :<, rendered.index('| USD estimate | $1.000000 |')
    assert_includes rendered, '<summary>Usage and cost · $3.58+ estimated</summary>'
    assert_includes rendered, '| **Total** | $3.58+ |  |'
    assert_includes rendered, 'reports from before this table are listed below and not counted'
  end

  def test_unreadable_carried_columns_are_reported
    block = "#{Shaka::UsageRecords.begin_mark(USAGE_RECORD)}\n<!-- usage-columns [ -->\n#{Shaka::UsageRecords::END_MARK}"
    error = assert_raises(Shaka::Error) do
      render(usage: usage_of(COLUMN).merge('carried' => block))
    end
    assert_includes error.message, 'unreadable columns'
  end
end
