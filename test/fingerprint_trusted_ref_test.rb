# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/configuration/fingerprint'
require 'fileutils'

class FingerprintTrustedRefTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('fingerprint-ref')
    FileUtils.mkdir_p(File.join(@root, '.agents'))
    File.write(File.join(@root, '.agents/agent-workflow.yml'), 'config')
    system('git', '-C', @root, 'init', '--quiet', exception: true)
    commit
  end

  def teardown = FileUtils.remove_entry(@root)

  def commit
    system('git', '-C', @root, 'add', '.agents', exception: true)
    system('git', '-C', @root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'config', exception: true)
    Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
  end

  def fingerprint(ref)
    settings = { 'commands' => {}, 'review' => {}, 'opening_check' => {},
                 'paths' => { 'policy_configuration' => '.agents/agent-workflow.yml' } }
    installation = { 'schema_version' => 1, 'version' => '1', 'source' => { 'kind' => 'uninstalled' } }
    Shaka::Configuration::Fingerprint.build(root: @root, effective_settings: settings,
                                            repository: 'shakacode/shaka', installation:, trusted_ref: ref)
  end

  def test_tree_sha_is_not_a_trusted_commit
    ref = Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
    tree = Open3.capture2('git', '-C', @root, 'rev-parse', "#{ref}^{tree}").first.strip
    assert_raises(Shaka::Error) { fingerprint(tree) }
  end

  def test_trusted_configuration_symlink_is_rejected
    config = File.join(@root, '.agents/agent-workflow.yml')
    File.write(File.join(@root, '.agents/real.yml'), 'config')
    File.delete(config)
    File.symlink('real.yml', config)
    assert_raises(Shaka::Error) { fingerprint(commit) }
  end
end
