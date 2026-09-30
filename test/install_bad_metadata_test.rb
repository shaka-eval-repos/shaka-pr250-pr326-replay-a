# frozen_string_literal: true

require_relative 'install_support'
require 'timeout'

class InstallBadMetadataTest < Minitest::Test
  include InstallTestSupport

  def test_top_level_non_object_metadata_fails_without_backtrace
    install!
    File.write(File.join(package_path, '.shaka-install.json'), '"edited"')
    assert_clean_rejection
  end

  def test_symlinked_managed_package_root_is_refused
    install!
    original = package_path
    moved = File.join(@directory, 'outside-package')
    FileUtils.mv(original, moved)
    File.symlink(moved, original)

    assert_clean_rejection
    output, status = run_installer('--skills-dir', @skills_dir, '--with-rct', '--rollback', File.basename(original))
    refute_predicate status, :success?
    assert_includes output, 'Managed package root is invalid'
  end

  def test_fifo_metadata_fails_promptly_on_reinstall_and_rollback
    install!
    metadata = File.join(package_path, '.shaka-install.json')
    File.unlink(metadata)
    assert system('mkfifo', metadata)

    Timeout.timeout(5) do
      assert_clean_rejection
      assert_fifo_rejected_on_rollback
    end
  end

  def test_non_object_source_metadata_fails_without_backtrace
    install!
    identity = package_identity
    identity['source'] = 'edited'
    File.write(File.join(package_path, '.shaka-install.json'), JSON.generate(identity))
    assert_clean_rejection
  end

  def test_doctor_rejects_missing_managed_package_id
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    identity = package_identity
    identity.delete('package_id')
    File.write(File.join(package_path, '.shaka-install.json'), JSON.generate(identity))

    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor', '--installation-json')
    refute_predicate status, :success?
    assert_includes output, 'Installed package metadata is invalid'
  end

  def test_doctor_rejects_metadata_that_disagrees_with_the_package_id
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    identity = package_identity
    identity['source']['content_sha256'] = '0' * 64
    File.write(File.join(package_path, '.shaka-install.json'), JSON.generate(identity))

    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor', '--installation-json')
    refute_predicate status, :success?
    assert_includes output, 'Installed package metadata is invalid'
  end

  def test_doctor_rejects_metadata_without_skill_selection
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    identity = package_identity
    identity.delete('skills')
    File.write(File.join(package_path, '.shaka-install.json'), JSON.generate(identity))

    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor', '--installation-json')
    refute_predicate status, :success?
    assert_includes output, 'Installed package metadata is invalid'
  end

  def test_doctor_rejects_empty_skill_selection
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    identity = package_identity
    identity['skills'] = []
    File.write(File.join(package_path, '.shaka-install.json'), JSON.generate(identity))

    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor', '--installation-json')
    refute_predicate status, :success?
    assert_includes output, 'Installed package metadata is invalid'
  end

  private

  def assert_fifo_rejected_on_rollback
    output, status = run_installer('--skills-dir', @skills_dir, '--with-rct',
                                   '--rollback', File.basename(package_path))
    refute_predicate status, :success?
    assert_includes output, 'Managed package metadata is invalid'
  end

  def install!
    output, status = install
    assert_predicate status, :success?, output
  end

  def assert_clean_rejection
    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Managed package'
    refute_includes output, 'from '
  end
end
