# frozen_string_literal: true

require_relative 'install_support'
require 'pathname'

class InstallMigrationTest < Minitest::Test
  include InstallTestSupport

  def test_replaces_old_checkout_link_with_managed_copy
    FileUtils.mkdir_p(@skills_dir)
    File.symlink(@source, @destination)

    output, status = install
    assert_predicate status, :success?, output
    refute_equal @source, File.readlink(@destination)
    assert_equal 'version one', File.read(File.join(@destination, 'SKILL.md'))
  end

  def test_replaces_relative_old_checkout_link_with_managed_copy
    FileUtils.mkdir_p(@skills_dir)
    relative = Pathname.new(@source).relative_path_from(Pathname.new(@skills_dir)).to_s
    File.symlink(relative, @destination)

    output, status = install
    assert_predicate status, :success?, output
    assert_equal 'version one', File.read(File.join(@destination, 'SKILL.md'))
  end
end
