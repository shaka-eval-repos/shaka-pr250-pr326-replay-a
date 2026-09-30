# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'configuration_layout_fixture'
require 'shaka/configuration/fingerprint'
require 'fileutils'
require 'find'

class FingerprintBoundaryTest < Minitest::Test
  include ConfigurationLayoutFixture

  def setup
    @root = Dir.mktmpdir('fingerprint-boundary')
    FileUtils.mkdir_p(File.join(@root, '.agents/shaka/bin'))
    create_new_commands(@root)
    File.write(File.join(@root, '.agents/shaka/config.yml'), YAML.dump(config))
    @settings = { 'commands' => {}, 'review' => {}, 'opening_check' => {},
                  'paths' => { 'policy_configuration' => '.agents/shaka/config.yml' } }
    @source = private_source
    @installation = { 'schema_version' => 1, 'version' => '1', 'source' => { 'kind' => 'uninstalled' } }
  end

  def teardown = FileUtils.remove_entry(@root)

  def private_source
    inventory = Find.find(File.join(@root, '.agents/shaka')).map { |path| { path: path.delete_prefix("#{@root}/") } }
    Struct.new(:root, :status, :ref, :inventory, :mode, :candidate_config).new(
      @root, 'complete', 'a' * 40, inventory, 'private/local', Shaka::RepositoryConfig.load(root: @root)
    )
  end

  def fingerprint(settings = @settings, **options)
    Shaka::Configuration::Fingerprint.build(root: @root, effective_settings: settings,
                                            repository: options.fetch(:repository, 'shakacode/shaka'),
                                            installation: options.fetch(:installation, @installation),
                                            private_source: @source)
  end

  def test_private_source_command_override_outside_inventory_is_hashed
    path = File.join(@root, 'ci.sh')
    File.write(path, 'first')
    settings = @settings.merge('commands' => { 'test' => 'ci.sh' })
    first = fingerprint(settings).components.fetch('files')
    File.write(path, 'second')
    refute_equal first, fingerprint(settings).components.fetch('files')
  end

  def test_rejects_incomplete_private_source_independently
    @source.status = 'partial'
    assert_raises(Shaka::Error) { fingerprint }
  end

  def test_wrong_settings_shapes_are_shaka_errors
    assert_raises(Shaka::Error) { fingerprint(@settings.merge('paths' => 'config.yml')) }
    assert_raises(Shaka::Error) { fingerprint(@settings.merge('commands' => [])) }
  end

  def test_invalid_repository_and_installation_are_rejected
    assert_raises(Shaka::Error) { fingerprint(repository: 'shaka') }
    assert_raises(Shaka::Error) { fingerprint(installation: @installation.merge('schema_version' => 2)) }
  end

  def test_malformed_private_inventory_reports_its_source
    @source.inventory << { 'path' => 'wrong key' }
    error = assert_raises(Shaka::Error) { fingerprint }
    assert_includes error.message, 'inventory'
  end

  def test_private_file_added_after_preflight_requires_new_resolution
    File.write(File.join(@root, '.agents/shaka/new-prompt.md'), 'new')
    error = assert_raises(Shaka::Error) { fingerprint }
    assert_includes error.message, 'since preflight'
  end

  def test_invalid_encoding_is_a_shaka_error
    settings = @settings.merge('note' => "\xFF".b)
    assert_raises(Shaka::Error) { fingerprint(settings) }
  end

  def test_rejects_unsafe_command_path
    settings = @settings.merge('commands' => { 'test' => '../outside' })
    assert_raises(Shaka::Error) { fingerprint(settings) }
  end

  def test_rejects_directory_command_path
    settings = @settings.merge('commands' => { 'test' => '.agents/shaka/bin' })
    assert_raises(Shaka::Error) { fingerprint(settings) }
  end

  def test_rejects_command_through_parent_symlink_outside_repository
    Dir.mktmpdir('outside-fingerprint') do |outside|
      File.write(File.join(outside, 'test'), 'external')
      File.symlink(outside, File.join(@root, 'link'))
      settings = @settings.merge('commands' => { 'test' => 'link/test' })
      assert_raises(Shaka::Error) { fingerprint(settings) }
    end
  end

  def test_rejects_trailing_slash_on_directory_symlink
    Dir.mktmpdir('outside-fingerprint') do |outside|
      File.symlink(outside, File.join(@root, 'escape-dir'))
      settings = @settings.merge('commands' => { 'test' => 'escape-dir/' })
      assert_raises(Shaka::Error) { fingerprint(settings) }
    end
  end

  def test_rejects_nul_byte_in_path
    settings = @settings.merge('commands' => { 'test' => "test\0path" })
    assert_raises(Shaka::Error) { fingerprint(settings) }
  end

  def test_rejects_wrong_worktree_and_symbolic_private_ref
    @source.root = Dir.tmpdir
    assert_raises(Shaka::Error) { fingerprint }
    @source.root = @root
    @source.ref = 'main'
    assert_raises(Shaka::Error) { fingerprint }
  end

  def test_source_selection_requires_exactly_one_source
    options = { root: @root, effective_settings: @settings, repository: 'shakacode/shaka',
                installation: @installation }
    builder = Shaka::Configuration::Fingerprint
    assert_raises(Shaka::Error) { builder.build(**options) }
    assert_raises(Shaka::Error) { builder.build(**options, private_source: @source, trusted_ref: 'a' * 40) }
  end
end
