# frozen_string_literal: true

require_relative 'install_support'

class InstallSkillsDirectoryModeTest < Minitest::Test
  include InstallTestSupport

  def test_new_skills_directory_is_safe_under_permissive_umask
    output, status = Open3.capture2e({ 'HOME' => @home }, RbConfig.ruby, '-e',
                                     'File.umask(0); load ARGV.shift', @installer,
                                     '--skills-dir', @skills_dir)

    assert_predicate status, :success?, output
    assert_equal 0o755, File.stat(@skills_dir).mode & 0o777
    assert_equal 0o755, File.stat(File.dirname(@skills_dir)).mode & 0o777
  end

  def test_existing_writable_skills_directory_is_rejected
    FileUtils.mkdir_p(@skills_dir)
    File.chmod(0o777, @skills_dir)

    output, status = install

    refute_predicate status, :success?
    assert_includes output, 'Host skills directory is unsafe'
    refute_path_exists @destination
  end

  def test_existing_writable_parent_is_rejected
    FileUtils.mkdir_p(@skills_dir)
    File.chmod(0o777, File.dirname(@skills_dir))

    output, status = install

    refute_predicate status, :success?
    assert_includes output, 'Host skills directory has an unsafe parent'
    refute_path_exists @destination
  end
end
