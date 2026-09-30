# frozen_string_literal: true

require_relative 'install_support'

class InstallManagedRootModeTest < Minitest::Test
  include InstallTestSupport

  def test_new_managed_directory_is_safe_under_permissive_umask
    managed = File.join(@directory, 'shaka', 'managed')
    output, status = Open3.capture2e({ 'HOME' => @home }, RbConfig.ruby, '-e',
                                     'File.umask(0); load ARGV.shift', @installer,
                                     '--skills-dir', @skills_dir, '--managed-dir', managed)

    assert_predicate status, :success?, output
    assert_equal 0o755, File.stat(managed).mode & 0o777
    assert_equal 0o755, File.stat(File.dirname(managed)).mode & 0o777
    assert_path_exists @destination
  end

  def test_existing_writable_managed_directory_is_rejected
    managed = File.join(@directory, 'managed')
    FileUtils.mkdir_p(managed)
    File.chmod(0o777, managed)

    output, status = run_installer('--skills-dir', @skills_dir, '--managed-dir', managed)

    refute_predicate status, :success?
    assert_includes output, 'Managed directory is unsafe'
    refute_path_exists @destination
  end

  def test_managed_directory_beneath_writable_parent_is_rejected
    [0o775, 0o777].each do |mode|
      parent = File.join(@directory, "parent-#{mode}")
      managed = File.join(parent, 'managed')
      FileUtils.mkdir_p(managed)
      File.chmod(mode, parent)

      output, status = run_installer('--skills-dir', @skills_dir, '--managed-dir', managed)

      refute_predicate status, :success?
      assert_includes output, 'unsafe parent'
      refute_path_exists @destination
    end
  end
end
