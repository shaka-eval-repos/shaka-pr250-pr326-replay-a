# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'rbconfig'

module WorkFixture
  def setup
    @directory = Dir.mktmpdir('shaka-launcher-test')
    @target = File.join(@directory, 'consumer repo')
    @nested = File.join(@target, 'nested')
    @capture = File.join(@directory, 'capture.json')
    FileUtils.mkdir_p([@nested, File.join(@directory, 'bin'), File.join(@directory, 'temp')])
    copy_source
    _output, error, status = Open3.capture3('git', 'init', '--quiet', @target)
    assert_predicate status, :success?, error
    write_codex
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

  def launch(*, directory: @nested, command: @command, temporary: File.join(@directory, 'temp'))
    environment = { 'PATH' => "#{@directory}/bin:#{ENV.fetch('PATH')}", 'WORK_CAPTURE' => @capture,
                    'TMPDIR' => temporary }
    Open3.capture3(environment, command, 'work', *, chdir: directory)
  end

  def write_codex
    executable = File.join(@directory, 'bin', 'codex')
    File.write(executable, <<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      File.write(ENV.fetch('WORK_CAPTURE'), JSON.generate(
        argv: ARGV, cwd: Dir.pwd, tmpdir: ENV['TMPDIR'], tmpprefix: ENV['TMPPREFIX']
      ))
    RUBY
    FileUtils.chmod(0o755, executable)
  end
end

class WorkTest < Minitest::Test
  include WorkFixture

  def test_starts_native_interactive_codex_in_a_private_session_with_its_own_temp
    capture = started('Fix the failing test')
    argv = capture.fetch('argv')
    session = argv[1]
    assert_equal 0o700, File.stat(session).mode & 0o777
    assert_equal session, capture['cwd']
    assert_equal ["#{session}/tmp", "#{session}/tmp/zsh"], capture.values_at('tmpdir', 'tmpprefix')
    assert_includes argv.last, 'Fix the failing test'
  end

  def test_overrides_extra_writable_roots_and_unrestricted_host_defaults
    argv = started('Fix the test').fetch('argv')
    assert_equal ['--cd', argv[1], '--add-dir', File.realpath(@target),
                  '--sandbox', 'workspace-write', '--ask-for-approval', 'on-request',
                  '-c', 'sandbox_workspace_write.writable_roots=[]',
                  '-c', 'sandbox_workspace_write.exclude_slash_tmp=true',
                  '-c', 'sandbox_workspace_write.exclude_tmpdir_env_var=true',
                  '-c', 'sandbox_workspace_write.network_access=false',
                  '-c', "shell_environment_policy.set.TMPDIR=#{JSON.generate("#{argv[1]}/tmp")}",
                  '-c', "shell_environment_policy.set.TMPPREFIX=#{JSON.generate("#{argv[1]}/tmp/zsh")}"], argv[0...-3]
  end

  def test_prompt_uses_absolute_trusted_skill_and_preserves_task_text_without_shell_expansion
    marker = File.join(@directory, 'injected')
    task = "Fix $(touch #{marker}); preserve \"quotes\" and\nnewlines"
    argv = started(task).fetch('argv')
    assert_includes argv.last, File.realpath(File.join(@source, 'SKILL.md'))
    assert_equal task, JSON.parse(argv.last.lines.last)
    refute_path_exists marker
  end

  def test_never_puts_a_trusted_skill_link_in_the_writable_session
    session = started('Fix the test').fetch('argv')[1]
    refute(Dir.glob("#{session}/**/*", File::FNM_DOTMATCH).any? { |path| File.symlink?(path) })
  end

  def test_session_pins_the_workflow_helper_and_launching_ruby
    argv = started('Fix the test').fetch('argv')
    assert_includes argv, "shell_environment_policy.set.SHAKA_RUBY=#{JSON.generate(File.realpath(RbConfig.ruby))}"
    assert_includes argv.last, JSON.generate(File.realpath(@command))
  end

  def test_prompt_keeps_the_codex_scratch_session_root_unchanged
    assert_includes started('Fix the test').fetch('argv').last, 'Keep this host session root unchanged'
  end

  def test_explicit_repo_resolves_a_symlink_from_outside_the_checkout
    alias_path = File.join(@directory, 'consumer alias')
    File.symlink(@target, alias_path)
    _output, error, status = launch('--repo', alias_path, 'Fix the test', directory: @directory)
    assert_predicate status, :success?, error
    argv = JSON.parse(File.read(@capture)).fetch('argv')
    assert_equal File.realpath(@target), argv[argv.index('--add-dir') + 1]
  end

  def test_requires_a_task_and_rejects_unknown_options_without_starting_codex
    [[], ['   '], ['--repo'], ['--unknown']].each do |arguments|
      _output, error, status = launch(*arguments)
      refute_predicate status, :success?
      assert_includes error, 'shaka work:'
      refute_path_exists @capture
    end
  end

  def test_help_works_outside_a_repository_without_launching_codex
    output, error, status = launch('--help', directory: @directory)
    assert_predicate status, :success?, error
    assert_includes output, 'shaka work'
    assert_includes output, '--repo'
    refute_path_exists @capture
  end
end

class WorkBoundaryTest < Minitest::Test
  include WorkFixture

  def test_refuses_to_launch_when_the_target_contains_the_trusted_workflow
    Open3.capture3('git', 'init', '--quiet', @source)
    _output, error, status = launch('--repo', @source, 'Fix the workflow')
    refute_predicate status, :success?
    assert_includes error, 'trusted workflow'
    refute_path_exists @capture
  end

  def test_refuses_session_scratch_inside_the_consumer_checkout
    _output, error, status = launch('Fix the test', temporary: @target)
    refute_predicate status, :success?
    assert_includes error, 'outside the target checkout'
    refute_path_exists @capture
    assert_empty Dir.glob(File.join(@target, 'shaka-work-*'))
  end

  def test_refuses_an_installed_skill_link_inside_the_writable_target
    parent = File.join(@target, 'installed skills')
    FileUtils.mkdir_p(parent)
    link = File.join(parent, 'shaka')
    File.symlink(File.realpath(@source), link)
    _output, error, status = launch('Fix the test', command: File.join(link, 'scripts', 'shaka'))
    refute_predicate status, :success?
    assert_includes error, 'trusted workflow'
    refute_path_exists @capture
    assert File.symlink?(link)
  end

  def test_refuses_a_lexical_target_alias_inside_the_trusted_source
    alias_path = File.join(@source, 'consumer alias')
    File.symlink(@target, alias_path)
    _output, error, status = launch('--repo', alias_path, 'Fix the test')
    refute_predicate status, :success?
    assert_includes error, 'trusted workflow'
    refute_path_exists @capture
  end

  def test_rejected_session_inside_the_trusted_source_is_removed_without_launching
    _output, error, status = launch('Fix the test', temporary: @source)
    refute_predicate status, :success?
    assert_includes error, 'trusted workflow'
    refute_path_exists @capture
    assert_empty Dir.glob(File.join(@source, 'shaka-work-*'))
  end

  def test_refuses_a_lexical_session_alias_inside_the_trusted_source
    alias_path = File.join(@source, 'temporary alias')
    File.symlink(File.join(@directory, 'temp'), alias_path)
    _output, error, status = launch('Fix the test', temporary: alias_path)
    refute_predicate status, :success?
    assert_includes error, 'trusted workflow'
    refute_path_exists @capture
    assert_empty Dir.glob(File.join(@directory, 'temp', 'shaka-work-*'))
  end
end
