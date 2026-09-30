# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'
require 'shaka/install/package'
require 'shaka/install/source'

class InstallSourceIntegrityTest < Minitest::Test
  include InstallTestSupport

  def test_hash_distinguishes_file_boundaries_from_embedded_null_bytes
    first = File.join(@source, 'a')
    second = File.join(@source, 'b')
    File.write(first, 'p')
    File.write(second, 'q')
    tree = Shaka::Install::Tree.new(['shaka'])
    original = tree.hash(File.join(@directory, 'source'))
    forged = forged_content(second)
    File.unlink(second)
    File.binwrite(first, forged)

    refute_equal original, tree.hash(File.join(@directory, 'source'))
  end

  def test_hash_distinguishes_a_directory_from_a_file_with_the_same_bytes
    path = File.join(@source, 'entry')
    FileUtils.mkdir_p(path)
    File.chmod(0o755, path)
    tree = Shaka::Install::Tree.new(['shaka'])
    original = tree.hash(File.join(@directory, 'source'))
    Dir.rmdir(path)
    File.write(path, 'directory')
    File.chmod(0o755, path)

    refute_equal original, tree.hash(File.join(@directory, 'source'))
  end

  def test_clean_filter_does_not_label_different_worktree_bytes_as_revision
    root = File.join(@directory, 'source')
    prepare_crlf_source(root)
    assert_equal '', git('-C', root, 'status', '--porcelain', '--', 'skills/shaka').strip

    output, status = install
    assert_predicate status, :success?, output
    assert_equal 'development', package_identity.fetch('source').fetch('kind')
  end

  def test_git_ignore_failure_does_not_copy_local_files
    root = File.join(@directory, 'source')
    git('init', '-q', root)
    File.write(File.join(root, '.gitignore'), "skills/shaka/.env\n")
    File.write(File.join(@source, '.env'), 'local secret')
    File.binwrite(File.join(root, '.git', 'index'), 'broken index')

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Cannot verify ignored skill files'
    refute_path_exists @destination
  end

  def test_nested_source_refuses_parent_repository_ignored_files
    unrelated_parent_repository
    File.write(File.join(@directory, '.gitignore'), "*.env\n")
    File.write(File.join(@source, '.env'), 'local secret')

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Nested source has ignored skill files'
    refute_path_exists @destination
  end

  def test_nested_source_refuses_broad_parent_ignore_rules
    unrelated_parent_repository
    File.write(File.join(@directory, '.gitignore'), "*\n")

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Nested source has ignored skill files'
    refute_path_exists @destination
  end

  def test_changed_source_version_aborts_before_publishing_package
    versions = %w[one two]
    source = Object.new
    source.define_singleton_method(:version) { versions.shift || 'two' }
    source.define_singleton_method(:identity) { |hash| { 'kind' => 'development', 'content_sha256' => hash } }
    managed = File.join(@directory, 'managed')
    package = Shaka::Install::Package.new(managed, source, ['shaka'], Shaka::Install::Tree.new(['shaka']))

    error = assert_raises(ArgumentError) { package.prepare(File.join(@directory, 'source')) }
    assert_includes error.message, 'Source version changed'
    assert_empty Dir.children(managed)
  end

  def test_mode_comparison_uses_file_bits_instead_of_current_user_access
    root = File.join(@directory, 'source')
    path = File.join(@source, 'SKILL.md')
    File.chmod(0o750, path)
    source = Shaka::Install::Source.new(root, ['shaka'], Shaka::Install::Tree.new(['shaka']))
    tracked = { 'skills/shaka/SKILL.md' => %w[100755 blob] }

    original_executable = File.method(:executable?)
    File.define_singleton_method(:executable?) { |_path| false }
    assert source.send(:matching_modes?, tracked)
  ensure
    File.define_singleton_method(:executable?, original_executable) if original_executable
  end

  private

  def forged_content(second)
    mode = (File.stat(second).mode & 0o777).to_s
    ['p', 'skills/shaka/b', mode, 'q'].join("\0")
  end

  def prepare_crlf_source(root)
    File.write(File.join(root, '.gitattributes'), "skills/shaka/SKILL.md text eol=crlf\n")
    File.write(File.join(@source, 'SKILL.md'), "version one\n")
    commit_source(root)
    File.binwrite(File.join(@source, 'SKILL.md'), "version one\r\n")
    git('-C', root, 'update-index', '--assume-unchanged', 'skills/shaka/SKILL.md')
  end

  def commit_source(root)
    git('init', '-q', root)
    git('-C', root, 'add', 'skills', '.gitattributes')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
  end
end
