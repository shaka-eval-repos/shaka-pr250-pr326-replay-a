# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/links'

class InstallTemporaryLinkTest < Minitest::Test
  include InstallTestSupport

  def test_failed_switch_preserves_preexisting_temporary_link
    target = File.join(@directory, 'package')
    FileUtils.mkdir_p(File.join(target, 'skills', 'shaka'))
    FileUtils.mkdir_p(@skills_dir)
    temporary = File.join(@skills_dir, ".shaka.shaka-#{Process.pid}")
    File.symlink('/preexisting', temporary)

    assert_raises(Errno::EEXIST) { links.switch_all(target) }
    assert_equal '/preexisting', File.readlink(temporary)
  end

  def test_failed_restore_preserves_preexisting_temporary_link
    FileUtils.mkdir_p(@skills_dir)
    temporary = File.join(@skills_dir, ".shaka.shaka-restore-#{Process.pid}")
    File.symlink('/preexisting', temporary)

    assert_raises(Errno::EEXIST) { links.send(:restore, 'shaka', '/previous') }
    assert_equal '/preexisting', File.readlink(temporary)
  end

  private

  def links
    Shaka::Install::Links.new(@skills_dir, File.join(@directory, 'managed'),
                              File.join(@directory, 'source'), ['shaka'])
  end
end
