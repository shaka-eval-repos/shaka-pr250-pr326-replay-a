# frozen_string_literal: true

# Proves description checks the supplied usage before an earlier report is carried into it.

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'

class CliDescriptionUsageTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = '`shaka description` now refuses hand-written usage.'
  REPO = { 'repo' => { 'full_name' => 'owner/repo' } }.freeze

  # Break: the published body's rendered report was carried beside a hand-written table,
  # so the table passed as rendered usage.
  def test_a_carried_report_does_not_admit_a_hand_written_table
    Dir.mktmpdir do |dir|
      _output, error, status = run_description(dir)

      refute_predicate status, :success?
      assert_includes error, 'usage object'
      refute_path_exists File.join(dir, 'published.md')
    end
  end

  private

  def description_content
    hand = { 'summary' => 'Usage', 'body' => "| Metric | Value |\n| --- | --- |\n| Responses | UNKNOWN |" }
    super.merge('details' => [hand])
  end

  def fake_gh
    existing = "<!-- shaka:begin -->\n<details>\n<summary>Usage</summary>\n\n" \
               "#{RenderedUsage.body("| Metric | Value |\n| --- | --- |\n| Total | 1 |")}\n\n" \
               "</details>\n<!-- shaka:end -->"
    pull = { 'body' => existing, 'head' => REPO.merge('sha' => 'c' * 40), 'base' => REPO }
    encoded = JSON.generate(pull).unpack1('H*')
    replaced = super.sub("puts JSON.generate('body' => '', 'head' => { 'sha' => 'c' * 40 })",
                         "puts [#{encoded.dump}].pack('H*')")
    raise 'fake gh pull response was not replaced' if replaced == super

    replaced
  end
end
