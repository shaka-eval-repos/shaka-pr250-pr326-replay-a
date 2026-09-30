# frozen_string_literal: true

require_relative 'install_support'

class InstallModeNormalizationTest < Minitest::Test
  include InstallTestSupport

  def test_group_writable_clean_checkout_keeps_revision_and_protects_copy
    commit_source
    File.chmod(0o664, File.join(@source, 'SKILL.md'))
    File.chmod(0o775, File.join(@source, 'scripts/shaka'))

    assert_installed_kind('revision')
    assert_mode 0o644, File.join(@destination, 'SKILL.md')
    assert_mode 0o755, File.join(@destination, 'scripts/shaka')
    assert_predicate install.last, :success?
  end

  def test_world_writable_source_is_development_and_copy_detects_later_tampering
    helper = File.join(@source, 'scripts/shaka')
    File.chmod(0o777, helper)

    assert_installed_kind('development')
    installed = File.join(@destination, 'scripts/shaka')
    assert_mode 0o755, installed
    assert_tampering_rejected(installed)
  end

  def test_setgid_source_directory_is_copied_without_setgid_or_group_write
    scripts = File.join(@source, 'scripts')
    File.chmod(0o2775, scripts)

    assert_installed_kind('development')
    assert_mode 0o755, File.join(@destination, 'scripts')
  end

  private

  def commit_source
    root = File.join(@directory, 'source')
    git('init', '-q', root)
    git('-C', root, 'add', 'skills')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
  end

  def assert_installed_kind(kind)
    output, status = install
    assert_predicate status, :success?, output
    assert_equal kind, package_identity.fetch('source').fetch('kind')
  end

  def assert_tampering_rejected(installed)
    File.chmod(0o777, installed)
    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Managed package content differs'
  end

  def assert_mode(expected, path)
    assert_equal expected, File.stat(path).mode & 0o777
  end
end
