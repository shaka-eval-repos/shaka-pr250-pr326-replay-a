# frozen_string_literal: true

require_relative 'install_support'

class InstallStageCleanupTest < Minitest::Test
  include InstallTestSupport

  def test_failed_copy_removes_stage_with_read_only_skill_directory
    root = File.realpath(File.join(@directory, 'source'))
    File.write(File.join(@source, 'SKILL.md'), "Use #{root}/bin/install")
    File.chmod(0o555, @source)

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Checkout reference in package'
    assert_empty Dir.children(File.join(@home, '.local/share/shaka/installs'))
  ensure
    File.chmod(0o755, @source) if File.directory?(@source)
  end
end
