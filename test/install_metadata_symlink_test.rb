# frozen_string_literal: true

require_relative 'install_support'

class InstallMetadataSymlinkTest < Minitest::Test
  include InstallTestSupport

  def test_reinstall_and_doctor_reject_symlinked_package_metadata
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    symlink_metadata
    assert_installer_rejects
    assert_doctor_rejects
  end

  private

  def symlink_metadata
    metadata = File.join(package_path, '.shaka-install.json')
    external = File.join(@directory, 'external-metadata.json')
    FileUtils.mv(metadata, external)
    File.symlink(external, metadata)
  end

  def assert_installer_rejects
    output, status = run_installer('--skills-dir', @skills_dir)
    refute_predicate status, :success?
    assert_includes output, 'Managed package metadata is invalid'
  end

  def assert_doctor_rejects
    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor', '--installation-json')
    refute_predicate status, :success?
    assert_includes output, 'Installed package metadata is invalid'
  end
end
