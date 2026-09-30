# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'
require 'shaka/claim'

class ClaimMissingSeamTest < Minitest::Test
  STATUS = Struct.new(:exitstatus)
  PR = { 'number' => 111, 'title' => 'Dup', 'url' => 'https://example/111',
         'headRefName' => 'jg-codex/36-restore' }.freeze
  HEAD = "aaa\trefs/heads/jg-claude/36-restore-workflow-lines\n"

  def test_cli_uses_the_default_template_when_the_seam_is_absent
    Dir.mktmpdir do |root|
      stdout, status = run_claim(root, prs: [PR], branches: HEAD)
      parsed = JSON.parse(stdout)

      assert_equal 0, status
      assert_equal '{login}-{host}/{issue}-{description}', parsed.fetch('branch_name')
      assert_equal 111, parsed.fetch('pull_requests').first.fetch('number')
      assert_includes parsed.fetch('branches'), 'jg-claude/36-restore-workflow-lines'
    end
  end

  def test_cli_fails_when_the_seam_is_malformed
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, '.agents'))
      File.write(File.join(root, '.agents', 'agent-workflow.yml'), "version: [\n")
      stdout, status, stderr = run_claim(root, prs: [], branches: '')

      assert_equal 1, status
      assert_includes stderr, 'agent-workflow.yml'
      assert_empty stdout
    end
  end

  def test_cli_fails_when_the_seam_parent_is_not_a_directory
    Dir.mktmpdir do |root|
      File.write(File.join(root, '.agents'), "not a directory\n")
      stdout, status, stderr = run_claim(root, prs: [], branches: '')

      assert_equal 1, status
      assert_includes stderr, 'agent-workflow.yml'
      assert_empty stdout
    end
  end

  def test_cli_fails_when_the_seam_is_a_broken_symlink
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, '.agents'))
      File.symlink('missing.yml', File.join(root, '.agents', 'agent-workflow.yml'))
      stdout, status, stderr = run_claim(root, prs: [], branches: '')

      assert_equal 1, status
      assert_includes stderr, 'agent-workflow.yml'
      assert_empty stdout
    end
  end

  private

  def run_claim(root, prs:, branches:)
    stdout = StringIO.new
    stderr = StringIO.new
    status = with_io(stdout, stderr) { Shaka::Claim.run(['36', '--root', root], runner: runner(prs, branches)) }
    [stdout.string, status, stderr.string]
  end

  def with_io(stdout, stderr)
    original = [$stdout, $stderr]
    $stdout = stdout
    $stderr = stderr
    yield
  ensure
    $stdout, $stderr = original
  end

  def runner(prs, branches)
    lambda do |argv, **|
      return [JSON.generate(prs), '', STATUS.new(0)] if argv[1] == 'pr'
      return [branches, '', STATUS.new(0)] if argv[1] == 'ls-remote'

      raise "Unexpected command: #{argv.inspect}"
    end
  end
end
