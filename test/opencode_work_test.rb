# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'rbconfig'

module OpencodeWorkFixture
  # A project Gemfile the session's own commands must still see; the fake host runs under it too.
  PROJECT_GEMFILE = File.expand_path('../Gemfile', __dir__)

  def setup
    @directory = Dir.mktmpdir('shaka-opencode-launcher-test')
    @target = File.join(@directory, 'consumer repo')
    @capture = File.join(@directory, 'capture.json')
    FileUtils.mkdir_p([@target, File.join(@directory, 'bin'), File.join(@directory, 'temp')])
    copy_source
    _output, error, status = Open3.capture3('git', 'init', '--quiet', @target)
    assert_predicate status, :success?, error
    write_opencode
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  private

  def copy_source
    @source = File.join(@directory, 'trusted source', 'shaka')
    @command = File.join(@source, 'scripts', 'shaka')
    FileUtils.mkdir_p(File.dirname(@source))
    FileUtils.cp_r(File.expand_path('../skills/shaka', __dir__), @source)
  end

  def started(*)
    _output, error, status = launch(*)
    assert_predicate status, :success?, error
    JSON.parse(File.read(@capture))
  end

  def launch(*, directory: @target, command: @command, temporary: File.join(@directory, 'temp'))
    environment = { 'PATH' => "#{@directory}/bin:#{ENV.fetch('PATH')}", 'WORK_CAPTURE' => @capture,
                    'TMPDIR' => temporary, 'BUNDLE_GEMFILE' => PROJECT_GEMFILE }
    Open3.capture3(environment, command, 'work', '--host', 'opencode', *, chdir: directory)
  end

  def write_opencode
    executable = File.join(@directory, 'bin', 'opencode')
    File.write(executable, <<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      File.write(ENV.fetch('WORK_CAPTURE'), JSON.generate(
        argv: ARGV, cwd: Dir.pwd, project_config: ENV['OPENCODE_DISABLE_PROJECT_CONFIG'], shaka_ruby: ENV['SHAKA_RUBY'],
        bundle_gemfile: ENV['BUNDLE_GEMFILE']
      ))
    RUBY
    FileUtils.chmod(0o755, executable)
  end
end

class OpencodeWorkTest < Minitest::Test
  include OpencodeWorkFixture

  def test_starts_the_native_interactive_tui_in_the_target_checkout
    capture = started('Fix the failing test')
    assert_equal File.realpath(@target), capture['cwd']
    assert_equal [File.realpath(@target), '--prompt', capture['argv'].last], capture['argv']
    assert_includes capture['argv'].last, 'Fix the failing test'
  end

  def test_prompt_uses_absolute_trusted_skill_and_preserves_task_text_without_shell_expansion
    marker = File.join(@directory, 'injected')
    task = "Fix $(touch #{marker}); preserve \"quotes\" and\nnewlines"
    prompt = started(task)['argv'].last
    assert_includes prompt, File.realpath(File.join(@source, 'SKILL.md'))
    assert_equal task, JSON.parse(prompt.lines.last)
    refute_path_exists marker
  end

  def test_refuses_project_local_components_from_the_target_checkout
    assert_equal 'true', started('Fix the test')['project_config']
  end

  def test_prompt_does_not_forbid_changing_the_checkout_opencode_runs_in
    prompt = started('Fix the test')['argv'].last
    assert_includes prompt, 'Keep the trusted workflow outside writable paths.'
    refute_includes prompt, 'Keep this host session root unchanged'
  end

  def test_session_pins_the_workflow_helper_and_launching_ruby
    capture = started('Fix the test')
    assert_equal File.realpath(RbConfig.ruby), capture['shaka_ruby']
    assert_equal PROJECT_GEMFILE, capture['bundle_gemfile'], 'project commands keep their Gemfile'
    assert_includes capture['argv'].last, JSON.generate(File.realpath(@command))
  end

  def test_help_names_the_host_option
    output, error, status = Open3.capture3({ 'PATH' => "#{@directory}/bin:#{ENV.fetch('PATH')}" },
                                           @command, 'work', '--help')
    assert_predicate status, :success?, error
    assert_includes output, '--host'
    assert_includes output, 'opencode'
  end

  def test_rejects_an_unknown_host_without_starting_opencode
    _output, error, status = launch('--host', 'pi', 'Fix the test')
    refute_predicate status, :success?
    assert_includes error, 'shaka work:'
    refute_path_exists @capture
  end

  def test_requires_a_task_without_starting_opencode
    _output, error, status = launch
    refute_predicate status, :success?
    assert_includes error, 'shaka work:'
    refute_path_exists @capture
  end

  def test_refuses_to_launch_when_the_target_contains_the_trusted_workflow
    Open3.capture3('git', 'init', '--quiet', @source)
    _output, error, status = launch('--repo', @source, 'Fix the workflow')
    refute_predicate status, :success?
    assert_includes error, 'trusted workflow'
    refute_path_exists @capture
  end
end
