# frozen_string_literal: true

require_relative 'install_support'
require 'json'

class InstallManagedTest < Minitest::Test
  include InstallTestSupport

  def test_upgrade_keeps_previous_package_for_rollback
    install!
    previous = File.readlink(@destination)
    File.write(File.join(@source, 'SKILL.md'), 'version two')
    install!

    assert_upgraded(previous)
    rollback!(File.basename(File.dirname(previous, 2)))
    assert_rolled_back(previous)
  end

  def test_modified_source_records_development_identity_and_hash
    unrelated_parent_repository
    install!
    identity = package_identity
    assert_equal 'development', identity.fetch('source').fetch('kind')
    assert_nil identity.fetch('source').fetch('repository')
    assert_match(/\A[0-9a-f]{64}\z/, identity.fetch('source').fetch('content_sha256'))
    refute_includes JSON.generate(identity), @directory
  end

  def test_clean_git_source_records_exact_revision
    revision = commit_source
    install!
    identity = package_identity.fetch('source')

    assert_equal 'revision', identity.fetch('kind')
    assert_equal revision, identity.fetch('revision')
    assert_nil identity.fetch('base_revision')
    install!
    rollback!(package_identity.fetch('package_id'))
  end

  def test_modified_git_source_records_base_revision
    revision = commit_source
    File.write(File.join(@source, 'SKILL.md'), 'modified')
    install!
    identity = package_identity.fetch('source')

    assert_equal 'development', identity.fetch('kind')
    assert_equal revision, identity.fetch('base_revision')
    assert_nil identity.fetch('revision')
  end

  def test_mode_only_change_is_recorded_as_development_when_git_ignores_file_modes
    commit_source
    git('-C', File.join(@directory, 'source'), 'config', 'core.fileMode', 'false')
    File.chmod(0o755, File.join(@source, 'SKILL.md'))
    install!

    assert_equal 'development', package_identity.fetch('source').fetch('kind')
  end

  def test_new_clean_revision_gets_its_own_package_even_with_same_skill_bytes
    commit_source
    install!
    previous = package_identity.fetch('package_id')
    root = File.join(@directory, 'source')
    File.write(File.join(root, 'README.md'), "New commit\n")
    git('-C', root, 'add', 'README.md')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'new revision')
    install!

    refute_equal previous, package_identity.fetch('package_id')
  end

  def test_rejects_symlink_inside_source_skill
    File.symlink(@installer, File.join(@source, 'checkout-helper'))
    refute_predicate install.last, :success?
    refute_path_exists @destination
  end

  def test_copied_helper_works_after_source_is_deleted
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    assert_no_package_symlinks
    FileUtils.rm_rf(File.join(@directory, 'source'))
    assert_installed_doctor_works_from_second_worktree
  end

  private

  def install!
    output, status = install
    assert_predicate status, :success?, output
  end

  def rollback!(id)
    output, status = run_installer('--skills-dir', @skills_dir, '--with-rct', '--rollback', id)
    assert_predicate status, :success?, output
  end

  def skill_text = File.read(File.join(@destination, 'SKILL.md'))

  def assert_upgraded(previous)
    refute_equal previous, File.readlink(@destination)
    assert_equal 'version two', skill_text
    assert File.directory?(File.dirname(previous, 2))
  end

  def assert_rolled_back(previous)
    assert_equal previous, File.readlink(@destination)
    assert_equal 'version one', skill_text
  end

  def commit_source
    File.write(File.join(@source, 'lib', 'shaka', 'version.rb'), "module Shaka\n  VERSION = '0.1.0-rc1'\nend\n")
    root = File.join(@directory, 'source')
    git('init', '-q', root)
    git('-C', root, 'add', 'skills')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
    git('-C', root, 'rev-parse', 'HEAD').strip
  end
end
