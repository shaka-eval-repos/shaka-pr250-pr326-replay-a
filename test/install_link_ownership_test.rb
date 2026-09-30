# frozen_string_literal: true

require_relative 'install_support'

class InstallLinkOwnershipTest < Minitest::Test
  include InstallTestSupport

  def test_dotdot_link_outside_managed_directory_is_foreign
    managed = File.join(@directory, 'managed')
    package_id = "0.1.0-#{'a' * 64}-#{'b' * 64}"
    foreign = File.join(managed, '..', 'elsewhere', package_id, 'skills', 'shaka')
    FileUtils.mkdir_p(@skills_dir)
    File.symlink(foreign, @destination)

    output, status = run_installer('--skills-dir', @skills_dir, '--managed-dir', managed)
    refute_predicate status, :success?
    assert_includes output, 'Refusing existing destination'
    assert_equal foreign, File.readlink(@destination)
  end

  def test_nested_package_link_is_foreign
    managed = File.join(File.realpath(@directory), 'managed')
    package_id = "0.1.0-#{'a' * 64}-#{'b' * 64}"
    foreign = File.join(managed, 'other', package_id, 'skills', 'shaka')
    FileUtils.mkdir_p(@skills_dir)
    File.symlink(foreign, @destination)

    output, status = run_installer('--skills-dir', @skills_dir, '--managed-dir', managed)
    refute_predicate status, :success?
    assert_includes output, 'Refusing existing destination'
    assert_equal foreign, File.readlink(@destination)
  end
end
