# frozen_string_literal: true

require_relative 'install_support'

class InstallUnicodeTest < Minitest::Test
  include InstallTestSupport

  def test_install_from_a_non_ascii_checkout_path
    move_source_to_unicode_path
    File.write(File.join(@source, 'SKILL.md'), 'café')

    output, status = install
    assert_predicate status, :success?, output
    assert_equal 'café', File.read(File.join(@destination, 'SKILL.md'))
  end

  private

  def move_source_to_unicode_path
    old_root = File.join(@directory, 'source')
    new_root = File.join(@directory, 'código', 'source')
    FileUtils.mkdir_p(File.dirname(new_root))
    FileUtils.mv(old_root, new_root)
    @source = File.join(new_root, 'skills', 'shaka')
    @rct_source = File.join(new_root, 'skills', 'rct')
    @installer = File.join(new_root, 'bin', 'install')
  end
end
