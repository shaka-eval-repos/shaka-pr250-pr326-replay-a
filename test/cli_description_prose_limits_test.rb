# frozen_string_literal: true

# Proves description reads prose limits from the trusted commit, whatever the candidate checkout holds.

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'

class CliDescriptionProseLimitsTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Replaced by each test.'

  def test_a_relative_root_keeps_the_trusted_limit
    @summary = sentence(40)
    with_repository('prose_limits' => { 'max_sentence_words' => 50 }) do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        _output, error, status = Dir.chdir(root) { run_description(dir, root: '.', ref: true) }

        assert_predicate status, :success?, error
      end
    end
  end

  def test_a_broken_candidate_layout_cannot_loosen_the_trusted_limit
    @summary = sentence(30)
    with_repository('prose_limits' => { 'max_sentence_words' => 20 }) do |root|
      commit(root)
      break_candidate_layout(root)
      Dir.mktmpdir do |dir|
        _output, error, status = run_description(dir, root:, ref: true)

        assert_refused_before_publication(dir, status, error)
      end
    end
  end

  private

  def description_content = super.merge('summary' => @summary)

  # Renders tables as tables and other blocks as paragraphs, enough for the prose limits to measure.
  def fake_gh
    super.sub("when 'markdown' then puts JSON.generate('<table></table>' * 10)", <<~'RUBY'.chomp)
      when 'markdown'
        blocks = request.fetch('text').split(/\n\s*\n/).map { |block| block.gsub(/^<!--.*-->\n/, '') }
        blocks = blocks.reject { |block| block.start_with?('<') }
        puts blocks.map { |block| block.start_with?('|') ? '<table></table>' : "<p>#{block}</p>" }.join
    RUBY
  end

  def assert_refused_before_publication(dir, status, error)
    refute_predicate status, :success?
    assert_includes error, 'a sentence has 30 words (limit 20)'
    refute_path_exists File.join(dir, 'published.md')
  end

  def break_candidate_layout(root)
    contract = File.join(root, '.agents/agent-workflow.yml')
    File.delete(contract)
    File.symlink(File.join(root, 'missing.yml'), contract)
  end

  def sentence(words) = "Alpha #{Array.new(words - 2, 'word').join(' ')} end."
end
