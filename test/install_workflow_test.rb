# frozen_string_literal: true

require_relative 'install_support'

class InstallWorkflowTest < Minitest::Test
  include InstallTestSupport

  def test_installed_workflow_links_resolve_after_source_is_deleted
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    FileUtils.rm_rf(File.join(@directory, 'source'))

    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'workflow', chdir: @directory)
    assert_predicate status, :success?, output
    assert_workflow_links(output)
  end

  private

  def assert_workflow_links(output)
    paths = output.scan(/\]\(<([^>]+)>\)/).flatten.select { |target| target.start_with?('/') }
    refute_empty paths
    paths.each { |target| assert_path_exists target.split('#', 2).first }
  end
end
