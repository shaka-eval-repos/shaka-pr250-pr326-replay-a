# frozen_string_literal: true

require_relative 'install_support'

class InstallOverlapTest < Minitest::Test
  include InstallTestSupport

  def test_managed_directory_inside_skills_directory_is_refused
    assert_overlap(@skills_dir, File.join(@skills_dir, '.shaka-packages'))
  end

  def test_skills_directory_inside_managed_directory_is_refused
    assert_overlap(File.join(@directory, 'managed', 'skills'), File.join(@directory, 'managed'))
  end

  def test_managed_directory_containing_source_checkout_is_refused
    output, status = run_installer('--skills-dir', @skills_dir, '--managed-dir', @directory)
    refute_predicate status, :success?
    assert_includes output, 'overlaps source checkout'
  end

  private

  def assert_overlap(skills, managed)
    output, status = run_installer('--skills-dir', skills, '--managed-dir', managed)
    refute_predicate status, :success?
    assert_includes output, 'Managed and skills directories overlap'
  end
end
