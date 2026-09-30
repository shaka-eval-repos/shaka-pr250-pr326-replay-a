# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/links'

class InstallRestoreFailureTest < Minitest::Test
  include InstallTestSupport

  def test_failed_restore_keeps_current_link
    output, status = install
    assert_predicate status, :success?, output
    original = File.readlink(@destination)
    replacement = File.join(@directory, 'replacement', 'skills', 'shaka')
    FileUtils.mkdir_p(replacement)
    File.unlink(@destination)
    File.symlink(replacement, @destination)
    linker = Shaka::Install::Links.new(@skills_dir, File.dirname(package_path), @source, %w[shaka rct])

    assert_raises(Errno::ENOSPC) { with_failed_restore_symlink { linker.send(:restore, 'shaka', original) } }
    assert_equal replacement, File.readlink(@destination)
  end

  private

  def with_failed_restore_symlink
    original = File.method(:symlink)
    File.define_singleton_method(:symlink) do |target, link|
      raise Errno::ENOSPC if link.include?('.shaka-restore-')

      original.call(target, link)
    end
    yield
  ensure
    File.define_singleton_method(:symlink, original) if original
  end
end
