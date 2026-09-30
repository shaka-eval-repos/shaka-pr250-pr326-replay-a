# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/configuration/fingerprint'
require 'fileutils'

class FingerprintTrustedSourceTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('fingerprint-trusted')
    FileUtils.mkdir_p(File.join(@root, '.agents/bin'))
    File.write(File.join(@root, '.agents/bin/test'), 'test')
    @settings = { 'commands' => { 'test' => '.agents/bin/test' }, 'review' => {}, 'opening_check' => {},
                  'paths' => { 'policy_configuration' => '.agents/agent-workflow.yml' } }
    @installation = { 'schema_version' => 1, 'version' => '1', 'source' => { 'kind' => 'uninstalled' } }
    system('git', '-C', @root, 'init', '--quiet', exception: true)
  end

  def teardown = FileUtils.remove_entry(@root)

  def commit_config(body)
    File.write(File.join(@root, '.agents/agent-workflow.yml'), body)
    system('git', '-C', @root, 'add', '.agents/agent-workflow.yml', exception: true)
    system('git', '-C', @root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'config', exception: true)
    Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
  end

  def fingerprint(ref, settings = @settings)
    Shaka::Configuration::Fingerprint.build(root: @root, effective_settings: settings,
                                            repository: 'shakacode/shaka', installation: @installation,
                                            trusted_ref: ref)
  end

  def test_configuration_blob_changes_source_component
    first = fingerprint(commit_config('first'))
    second = fingerprint(commit_config('second'))
    refute_equal first.components.fetch('source'), second.components.fetch('source')
    assert_equal first.components.fetch('files'), second.components.fetch('files')
  end

  def prompt_fixture
    commit_config('first')
    path = File.join(@root, 'review.md')
    File.write(path, 'one')
    settings = @settings.merge('review' => { 'prompt_file' => 'review.md' })
    [path, commit_prompt, settings]
  end

  def files(result) = result.components.fetch('files')

  def test_candidate_prompt_edit_or_deletion_keeps_trusted_file_component
    path, ref, settings = prompt_fixture
    first = files(fingerprint(ref, settings))
    File.write(path, 'two')
    assert_equal first, files(fingerprint(ref, settings))
    File.delete(path)
    assert_equal first, files(fingerprint(ref, settings))
  end

  def test_committed_prompt_change_updates_file_component
    path, ref, settings = prompt_fixture
    first = files(fingerprint(ref, settings))
    File.write(path, 'two')
    refute_equal first, files(fingerprint(commit_prompt, settings))
  end

  def test_shared_command_and_prompt_path_includes_candidate_and_trusted_bytes
    path, ref, settings = prompt_fixture
    settings = settings.merge('commands' => { 'test' => 'review.md' })
    first = files(fingerprint(ref, settings))
    File.write(path, 'two')
    second = files(fingerprint(ref, settings))
    refute_equal first, second
    refute_equal second, files(fingerprint(commit_prompt, settings))
  end

  def trusted_symlink_fixture
    commit_config('first')
    target = 'révision.md'
    File.write(File.join(@root, target), 'instructions')
    File.symlink(target, File.join(@root, 'review.md'))
    ref = commit_prompt_with_target(target)
    settings = @settings.merge('review' => { 'prompt_file' => 'review.md' })
    [target, ref, settings]
  end

  def test_trusted_symlink_prompt_with_utf8_target
    target, ref, settings = trusted_symlink_fixture
    first = files(fingerprint(ref, settings))
    File.write(File.join(@root, target), 'revised instructions')
    refute_equal first, files(fingerprint(commit_prompt_with_target(target), settings))
  end

  def test_trusted_symlink_retarget_changes_identity_with_same_bytes
    _target, ref, settings = trusted_symlink_fixture
    replacement = 'copy.md'
    File.write(File.join(@root, replacement), 'instructions')
    File.delete(File.join(@root, 'review.md'))
    File.symlink(replacement, File.join(@root, 'review.md'))
    refute_equal files(fingerprint(ref, settings)), files(fingerprint(commit_prompt_with_target(replacement), settings))
  end

  def commit_prompt_with_target(target)
    paths = ['review.md']
    paths << target if target
    system('git', '-C', @root, 'add', *paths, exception: true)
    system('git', '-C', @root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'prompt', exception: true)
    Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
  end

  def commit_prompt = commit_prompt_with_target(nil)

  def test_symbolic_ref_and_missing_configuration_are_rejected
    assert_raises(Shaka::Error) { fingerprint('main') }
    assert_raises(Shaka::Error) { fingerprint('a' * 40) }
  end

  def test_configuration_path_must_name_a_blob
    ref = commit_config('first')
    settings = @settings.merge('paths' => { 'policy_configuration' => '.agents' })
    assert_raises(Shaka::Error) { fingerprint(ref, settings) }
  end
end
