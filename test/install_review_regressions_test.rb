# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'
require 'shaka/install/source'
require 'shaka/install/package'

class InstallReviewRegressionsTest < Minitest::Test
  include InstallTestSupport

  def test_git_discovery_failure_does_not_copy_local_files
    root = File.join(@directory, 'source')
    FileUtils.mkdir_p(File.join(root, '.git'))
    File.write(File.join(@source, '.env'), 'local secret')

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Cannot verify Git source checkout'
    refute_path_exists @destination
  end

  def test_writable_file_modes_cannot_claim_an_exact_revision
    root = File.join(@directory, 'source')
    path = File.join(@source, 'SKILL.md')
    source = Shaka::Install::Source.new(root, ['shaka'], Shaka::Install::Tree.new(['shaka']))

    File.chmod(0o666, path)
    refute source.send(:matching_modes?, { 'skills/shaka/SKILL.md' => %w[100644 blob] })
    File.chmod(0o777, path)
    refute source.send(:matching_modes?, { 'skills/shaka/SKILL.md' => %w[100755 blob] })
  end

  def test_source_change_after_copy_aborts_before_publishing_package
    root = File.join(@directory, 'source')
    tree = mutating_tree
    source = Shaka::Install::Source.new(root, ['shaka'], tree)
    managed = File.join(@directory, 'managed')
    package = Shaka::Install::Package.new(managed, source, ['shaka'], tree)

    error = assert_raises(ArgumentError) { package.prepare(root) }
    assert_includes error.message, 'Source changed during installation'
    assert_empty Dir.children(managed)
  end

  def test_missing_skill_entry_point_refuses_installation
    File.unlink(File.join(@source, 'SKILL.md'))
    assert_missing_entry_point
  end

  def test_missing_helper_entry_point_refuses_installation
    File.unlink(File.join(@source, 'scripts/shaka'))
    assert_missing_entry_point
  end

  def test_nonexecutable_helper_refuses_installation
    File.chmod(0o644, File.join(@source, 'scripts/shaka'))

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Skill helper is not executable'
    refute_path_exists @destination
  end

  private

  def mutating_tree
    Class.new(Shaka::Install::Tree) do
      def copy(source, target)
        super
        File.write(File.join(source, 'skills/shaka/SKILL.md'), 'changed after copy')
      end
    end.new(['shaka'])
  end

  def assert_missing_entry_point
    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Missing skill entry point'
    refute_path_exists @destination
  end
end
