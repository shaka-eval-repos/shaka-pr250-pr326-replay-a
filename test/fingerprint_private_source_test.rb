# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'configuration_layout_fixture'
require 'shaka/configuration'
require 'shaka/configuration/fingerprint'
require 'shaka/doctor'

class FingerprintPrivateSourceTest < Minitest::Test
  include ConfigurationLayoutFixture

  def setup
    @root = Dir.mktmpdir('fingerprint-t1')
    commit_project
    create_private_seam
  end

  def teardown = FileUtils.remove_entry(@root)

  def commit_project
    system('git', '-C', @root, 'init', '--quiet', exception: true)
    File.write(File.join(@root, 'README.md'), 'project')
    system('git', '-C', @root, 'add', 'README.md', exception: true)
    system('git', '-C', @root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'project', exception: true)
  end

  def create_private_seam
    FileUtils.mkdir_p(File.join(@root, '.agents/shaka/bin'))
    create_new_commands(@root)
    File.write(File.join(@root, '.agents/shaka/config.yml'), YAML.dump(config))
  end

  def test_consumes_complete_t1_private_source_without_promoting_trust
    ref = Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
    source = Shaka::Configuration.private_source(root: @root, ref:)
    assert_equal 'complete', source.status
    result = fingerprint(source)
    assert_equal 1, result.version
    assert result.components.fetch('files').key?('.agents/shaka/bin/test')
    assert_false source.grants_policy?
  end

  def test_config_change_after_preflight_requires_new_resolution
    ref = Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
    source = Shaka::Configuration.private_source(root: @root, ref:)
    path = File.join(@root, '.agents/shaka/config.yml')
    changed = YAML.safe_load_file(path)
    changed.fetch('review')['ci_review_wait'] = 'all'
    File.write(path, YAML.dump(changed))
    assert_raises(Shaka::Error) { fingerprint(source) }
  end

  def test_symlink_replacement_after_preflight_requires_new_resolution
    ref = Open3.capture2('git', '-C', @root, 'rev-parse', 'HEAD').first.strip
    source = Shaka::Configuration.private_source(root: @root, ref:)
    replacement = File.join(@root, 'uncommitted-script')
    File.write(replacement, 'new')
    command = File.join(@root, '.agents/shaka/bin/test')
    File.delete(command)
    File.symlink(replacement, command)
    assert_raises(Shaka::Error) { fingerprint(source) }
  end

  def fingerprint(source)
    Shaka::Configuration::Fingerprint.build(
      root: @root, effective_settings: source.candidate_config.to_h,
      repository: 'shakacode/shaka', installation: Shaka::Doctor::InstallationIdentity.read,
      private_source: source
    )
  end
end
