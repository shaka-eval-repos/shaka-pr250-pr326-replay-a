# frozen_string_literal: true

require_relative 'install_support'

class InstallSourceBatchTest < Minitest::Test
  include InstallTestSupport

  def test_exact_revision_with_many_files_and_newline_in_filename
    root = File.join(@directory, 'source')
    commit_many_files(root)

    output, status = install
    assert_predicate status, :success?, output
    assert_equal 'revision', package_identity.fetch('source').fetch('kind')
    assert_equal git('-C', root, 'rev-parse', 'HEAD').strip, package_identity.fetch('source').fetch('revision')
  end

  def test_empty_skill_directory_makes_revision_development
    root = File.join(@directory, 'source')
    commit_many_files(root)
    FileUtils.mkdir_p(File.join(@source, 'scratch'))

    output, status = install
    assert_predicate status, :success?, output
    assert_equal 'development', package_identity.fetch('source').fetch('kind')
  end

  def test_ignored_skill_directory_does_not_change_revision_identity
    root = File.join(@directory, 'source')
    prepare_ignored_directory(root)

    output, status = install
    assert_predicate status, :success?, output
    assert_equal 'revision', package_identity.fetch('source').fetch('kind')
    refute_path_exists File.join(package_path, 'skills', 'shaka', 'tmp')
  end

  private

  def prepare_ignored_directory(root)
    File.write(File.join(root, '.gitignore'), "skills/shaka/tmp/\n")
    commit_many_files(root)
    ignored = File.join(@source, 'tmp')
    FileUtils.mkdir_p(ignored)
    File.write(File.join(ignored, 'local.txt'), 'ignore me')
  end

  def commit_many_files(root)
    File.write(File.join(root, '.gitattributes'), '')
    105.times { |number| File.write(File.join(@source, "file-#{number}"), number.to_s) }
    File.write(File.join(@source, "line\nbreak"), 'content')
    git('init', '-q', root)
    paths = ['skills', '.gitattributes']
    paths << '.gitignore' if File.exist?(File.join(root, '.gitignore'))
    git('-C', root, 'add', *paths)
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
  end
end
