# frozen_string_literal: true

require_relative 'install_support'

class InstallSpecialModeTest < Minitest::Test
  include InstallTestSupport

  def test_source_with_setuid_bit_cannot_claim_an_exact_revision
    root = File.join(@directory, 'source')
    skill = File.join(@source, 'SKILL.md')
    commit_executable_source(root, skill)
    File.chmod(0o4755, skill)
    assert_equal '', git('-C', root, 'status', '--porcelain', '--', 'skills').strip

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Special permission bits in skill'
    refute_path_exists @destination
  end

  def test_changed_special_bit_invalidates_an_existing_package
    output, status = install
    assert_predicate status, :success?, output
    skill = File.join(package_path, 'skills', 'shaka', 'SKILL.md')
    File.chmod(0o4644, skill)

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Special permission bits in skill'
  end

  private

  def commit_executable_source(root, skill)
    File.chmod(0o755, skill)
    git('init', '-q', root)
    git('-C', root, 'add', 'skills')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
  end
end
