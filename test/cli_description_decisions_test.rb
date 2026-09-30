# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'

module CliDescriptionDecisionsRun
  def run_description(dir, root:, env: {}, decisions: true)
    @decisions = decisions == true ? ['Which base?'] : decisions
    write_fake_commands(dir)
    content = File.join(dir, 'content.json')
    File.write(content, JSON.generate(description_content))
    options = ['--root', root, '--content-file', content, '--ref', fixture_ref(root)]
    Open3.capture3({ 'PATH' => "#{dir}:#{ENV.fetch('PATH')}", 'HOME' => dir }.merge(env),
                   self.class::COMMAND, 'description', 'owner/repo', '1', *options)
  end

  def description_content
    content = super
    content['decisions'] = @decisions if @decisions
    content
  end
end

class CliDescriptionDecisionsTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes
  include CliDescriptionDecisionsRun

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Decisions stay with the label.'

  def test_description_applies_awaiting_answer_when_decisions_are_present
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        output, error, status = run_description(dir, root:)

        assert_predicate status, :success?, error
        assert_includes File.read(File.join(dir, 'published.md')), '## Decisions for the maintainer'
        assert_equal 'awaiting-answer', File.read(File.join(dir, 'labeled')).strip
        assert_equal ['awaiting-answer'], JSON.parse(output).dig('attention', 'labels')
      end
    end
  end

  def test_description_refuses_decisions_on_a_closed_pull_request_before_writing
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        _output, error, status = run_description(dir, root:, env: { 'PR_STATE' => 'CLOSED' })

        refute_predicate status, :success?
        assert_includes error, 'not open'
        refute_path_exists File.join(dir, 'published.md')
        refute_path_exists File.join(dir, 'labeled')
      end
    end
  end

  def test_description_refuses_decisions_while_awaiting_merge_approval
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        env = { 'PR_LABEL' => 'awaiting-merge-approval' }
        _output, error, status = run_description(dir, root:, env:)

        refute_predicate status, :success?
        assert_includes error, 'awaiting-merge-approval'
        refute_path_exists File.join(dir, 'published.md')
      end
    end
  end

  def test_description_does_not_label_when_a_decision_is_blank
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        _output, error, status = run_description(dir, root:, decisions: ['  '])

        refute_predicate status, :success?
        assert_includes error, 'decision'
        refute_path_exists File.join(dir, 'published.md')
        refute_path_exists File.join(dir, 'labeled')
      end
    end
  end

  def test_description_refuses_to_drop_decisions_that_are_already_published
    body = "<!-- shaka:decisions -->\n## Decisions for the maintainer\n\n- Which base?\n"
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        _output, error, status = run_description(dir, root:, decisions: false, env: { 'EXISTING_BODY' => body })

        refute_predicate status, :success?
        assert_includes error, 'empty list'
        refute_path_exists File.join(dir, 'published.md')
      end
    end
  end

  def test_description_without_decisions_does_not_touch_labels
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        _output, error, status = run_description(dir, root:, decisions: false)

        assert_predicate status, :success?, error
        log = File.read(File.join(dir, 'gh-log'))
        refute_includes log, 'labels'
        refute_path_exists File.join(dir, 'labeled')
      end
    end
  end

  def test_an_empty_decisions_list_removes_the_section_and_the_label
    prior = "<!-- shaka:begin -->\n<!-- shaka:decisions -->\n<!-- shaka:end -->\n"
    env = { 'EXISTING_BODY' => prior, 'PR_LABEL' => 'awaiting-answer' }
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_decisions_cleared(dir, root, env) }
    end
  end

  private

  def assert_decisions_cleared(dir, root, env)
    output, error, status = run_description(dir, root:, decisions: [], env:)
    assert_predicate status, :success?, error
    refute_includes File.read(File.join(dir, 'published.md')), 'shaka:decisions'
    assert_equal 'deleted', File.read(File.join(dir, 'released')).strip
    assert_equal 'released', JSON.parse(output).dig('attention', 'state')
  end

  def fake_gh = DESCRIPTION_GH
end

DESCRIPTION_GH = <<~'RUBY'
  require 'json'
  raw = STDIN.read
  request = raw.empty? ? {} : JSON.parse(raw)
  File.open(File.join(ENV.fetch('HOME'), 'gh-log'), 'a') { |file| file.puts ARGV.inspect }
  path = ARGV[1].to_s
  case path
  when 'repos/owner/repo/pulls/1'
    if ARGV.include?('PATCH')
      File.write(File.join(ENV.fetch('HOME'), 'published.md'), request.fetch('body'))
      puts JSON.generate(request)
    else
      puts JSON.generate('body' => ENV.fetch('EXISTING_BODY', ''),
                         'head' => { 'sha' => 'c' * 40, 'repo' => { 'full_name' => 'owner/repo' } },
                         'base' => { 'repo' => { 'full_name' => 'owner/repo' } })
    end
  when 'markdown' then puts JSON.generate('<table></table>' * 10)
  when 'graphql'
    state = ENV.fetch('PR_STATE', 'OPEN')
    puts JSON.generate('data' => { 'repository' => { 'pullRequest' => { 'state' => state } } })
  when %r{issues/1/labels\?}
    name = ENV['PR_LABEL'].to_s
    puts JSON.generate(name.empty? ? [] : [{ 'name' => name }])
  when %r{issues/1/labels\z}
    File.write(File.join(ENV.fetch('HOME'), 'labeled'), request.fetch('labels').join(','))
    puts JSON.generate([{ 'name' => 'awaiting-answer' }])
  when %r{issues/1/labels/}
    abort "unexpected label write: #{ARGV.inspect}" unless ARGV.include?('DELETE')

    File.write(File.join(ENV.fetch('HOME'), 'released'), 'deleted')
    puts '[]'
  when 'repos/owner/repo/labels/awaiting-answer'
    puts JSON.generate('name' => 'awaiting-answer')
  else
    abort "unexpected gh request: #{ARGV.inspect} #{raw}"
  end
RUBY
