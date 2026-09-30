# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'

class DocsOnlyChangeTestSupport < Minitest::Test
  SCRIPT = File.expand_path('../bin/docs-only-change', __dir__)
  REAL_GIT = TEST_GIT

  def setup
    @root = Dir.mktmpdir('docs-only-change')
    initialize_repository
    @main = git('branch', '--show-current').strip
    @base = git('rev-parse', 'HEAD').strip
  end

  def initialize_repository
    git('init', '-q')
    git('config', 'user.email', 'test@example.com')
    git('config', 'user.name', 'Test User')
    write('README.md', "Hello\n")
    write('docs/guide.md', "Guide\n")
    write('lib/example.rb', "puts :example\n")
    git('add', '.')
    git('commit', '-qm', 'Initial')
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  private

  def classify(base = @base, environment = {})
    Open3.capture2e(environment, SCRIPT, base, chdir: @root)
  end

  def commit_change(path, content, message)
    write(path, content)
    git('add', '.')
    git('commit', '-qm', message)
  end

  def commit_executable_document
    FileUtils.chmod(0o755, File.join(@root, 'docs/guide.md'))
    git('add', 'docs/guide.md')
    git('commit', '-qm', 'Make documentation executable')
    git('rev-parse', 'HEAD').strip
  end

  def git(*)
    output, status = Open3.capture2e('git', *, chdir: @root)
    raise output unless status.success?

    output
  end

  def write(path, content)
    destination = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(destination))
    File.write(destination, content)
  end

  def fake_git_that_fails_diff
    directory = File.join(@root, '.git/fake-bin')
    write('.git/fake-bin/git', "#!/bin/sh\n[ \"$1\" = diff ] && exit 1\nexec \"#{REAL_GIT}\" \"$@\"\n")
    FileUtils.chmod(0o755, File.join(directory, 'git'))
    directory
  end
end

class DocsOnlyChangeTest < DocsOnlyChangeTestSupport
  def test_accepts_readme_and_docs_changes
    write('README.md', "Hello human\n")
    write('docs/guide.md', "Better guide\n")
    output, status = classify
    assert_predicate status, :success?, output
    assert_includes output, 'Documentation-only change'
  end

  def test_accepts_an_untracked_doc
    write('docs/new.md', "New\n")
    _output, status = classify
    assert_predicate status, :success?
  end

  def test_accepts_docs_branch_when_the_base_branch_has_newer_code
    git('checkout', '-qb', 'docs-branch')
    commit_change('docs/guide.md', "Better guide\n", 'Update docs')
    git('checkout', '-q', @main)
    commit_change('lib/example.rb', "puts :newer_main\n", 'Advance main')
    newer_base = git('rev-parse', 'HEAD').strip
    git('checkout', '-q', 'docs-branch')
    output, status = classify(newer_base)
    assert_predicate status, :success?, output
  end

  def test_rejects_mixed_changes
    write('docs/guide.md', "Better guide\n")
    write('lib/example.rb', "puts :changed\n")
    _output, status = classify
    refute_predicate status, :success?
  end

  def test_rejects_staged_code_hidden_by_the_working_tree
    write('docs/guide.md', "Better guide\n")
    write('lib/example.rb', "puts :staged\n")
    git('add', 'lib/example.rb')
    write('lib/example.rb', "puts :example\n")

    _output, status = classify

    refute_predicate status, :success?
  end

  def test_rejects_instruction_markdown
    write('AGENTS.md', "Instructions\n")
    _output, status = classify
    refute_predicate status, :success?
  end

  def test_rejects_non_markdown_files_under_docs
    write('docs/tool.rb', "puts :tool\n")
    _output, status = classify
    refute_predicate status, :success?
  end

  def test_rejects_executable_markdown
    FileUtils.chmod(0o755, File.join(@root, 'docs/guide.md'))
    _output, status = classify
    refute_predicate status, :success?
  end

  def test_rejects_an_untracked_broken_symlink
    File.symlink('missing.md', File.join(@root, 'docs/broken.md'))
    _output, status = classify
    refute_predicate status, :success?
  end
end

class DocsOnlyChangeBaseModeTest < DocsOnlyChangeTestSupport
  def test_rejects_an_incomplete_inventory
    write('docs/new.md', "New\n")
    environment = { 'PATH' => "#{fake_git_that_fails_diff}:#{ENV.fetch('PATH')}" }
    _output, status = classify(@base, environment)
    refute_predicate status, :success?
  end

  def test_rejects_an_unmerged_document
    git('checkout', '-qb', 'other')
    commit_change('docs/guide.md', "Other\n", 'Other change')
    git('checkout', '-q', @main)
    commit_change('docs/guide.md', "Main\n", 'Main change')
    _output, merge = Open3.capture2e('git', 'merge', 'other', chdir: @root)

    refute_predicate merge, :success?
    _output, status = classify
    refute_predicate status, :success?
  end

  def test_rejects_normalizing_executable_markdown
    executable_base = commit_executable_document
    FileUtils.chmod(0o644, File.join(@root, 'docs/guide.md'))
    _output, status = classify(executable_base)
    refute_predicate status, :success?
  end

  def test_rejects_deleting_executable_markdown
    executable_base = commit_executable_document
    FileUtils.rm(File.join(@root, 'docs/guide.md'))
    _output, status = classify(executable_base)
    refute_predicate status, :success?
  end

  def test_rejects_a_rename_from_code_into_docs
    FileUtils.mv(File.join(@root, 'lib/example.rb'), File.join(@root, 'docs/example.rb'))

    _output, status = classify

    refute_predicate status, :success?
  end

  def test_rejects_empty_changes_and_unknown_bases
    _output, unchanged = classify
    _output, unknown = classify('missing-base')

    refute_predicate unchanged, :success?
    refute_predicate unknown, :success?
  end
end
