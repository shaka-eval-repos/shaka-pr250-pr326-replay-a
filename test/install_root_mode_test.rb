# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'

class InstallRootModeTest < Minitest::Test
  include InstallTestSupport

  def test_hash_records_the_skill_root_mode
    tree = Shaka::Install::Tree.new(['shaka'])
    root = File.join(@directory, 'source')
    original = tree.hash(root)
    File.chmod(0o700, @source)

    refute_equal original, tree.hash(root)
  end

  def test_copy_preserves_root_mode_and_reinstall_detects_tampering
    File.chmod(0o700, @source)
    output, status = install
    assert_predicate status, :success?, output
    installed = File.join(package_path, 'skills', 'shaka')
    assert_equal 0o700, File.stat(installed).mode & 0o777
    File.chmod(0o777, installed)

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Managed package content differs'
  end

  def test_published_package_root_and_metadata_are_readable
    output, status = install
    assert_predicate status, :success?, output

    assert_mode 0o755, package_path
    assert_mode 0o755, File.join(package_path, 'skills')
    assert_mode 0o644, File.join(package_path, '.shaka-install.json')
  end

  def test_reinstall_rejects_writable_skills_container
    output, status = install
    assert_predicate status, :success?, output
    File.chmod(0o777, File.join(package_path, 'skills'))

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Managed package skills directory is invalid'
  end

  private

  def assert_mode(expected, path)
    assert_equal expected, File.stat(path).mode & 0o777
  end
end
