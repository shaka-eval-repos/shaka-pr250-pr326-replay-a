# frozen_string_literal: true

require_relative 'usage_test'

class UsageFormatTest < Minitest::Test
  include UsageFixture

  def test_json_format_reports_one_column_per_configuration
    column = json_report.fetch('columns').fetch(0)
    assert_equal 'gpt-test implementation', column.fetch('label')
    assert_equal %w[openai gpt-test high], column.values_at('provider', 'model', 'effort')
    assert_equal %w[100 40 20 5 UNKNOWN],
                 column.values_at('input', 'cached_input', 'output', 'reasoning_output', 'cache_writes')
  end

  def test_json_format_keeps_the_note_and_record
    document = json_report
    assert_equal 'implementation', document.dig('record', 'contribution')
    assert_equal document.fetch('columns'), document.dig('record', 'columns')
    assert_includes document.fetch('note'), 'Native usage is PARTIAL.'
  end

  # Break: a carried report kept its price but lost its rate card and coverage gaps.
  def test_the_record_keeps_its_own_note
    note = json_report.dig('record', 'note')
    assert_includes note, 'Rate card:'
    assert_includes note, 'Native usage is PARTIAL.'
    refute_match(/\d+ responses?\./, note)
    # Break: the JSON note dropped the host caveat the Markdown report prints.
    assert_includes note, 'Cached input is part of input; reasoning output is part of output.'
  end

  def json_report
    JSON.parse(run_report([context('current'), usage('current', 'current', 100)], '--format', 'json'))
  end

  def test_json_with_no_responses_uses_unknown_not_zero
    column = JSON.parse(run_report([], '--format', 'json')).fetch('columns').fetch(0)
    assert_equal 'UNKNOWN', column.fetch('input')
    assert_equal 'UNKNOWN', column.fetch('usd')
  end

  def test_markdown_stays_the_default
    report = run_report([context('current'), usage('current', 'current', 100)])
    assert_includes report, '<!-- shaka:usage '
    refute_includes report, '"columns"'
  end
end
