# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/evidence/candidate_tree'
require 'fileutils'

class CandidateTreeTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('shaka-candidate-tree')
    system('git', '-C', @root, 'init', '--quiet', exception: true)
    File.write(File.join(@root, 'tracked'), 'before')
    system('git', '-C', @root, 'add', 'tracked', exception: true)
    system('git', '-C', @root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'initial', exception: true)
  end

  def teardown = FileUtils.remove_entry(@root)

  def git(*)
    output, status = Open3.capture2('git', '-C', @root, *)
    assert_predicate status, :success?
    output.strip
  end

  def test_captures_staged_unstaged_and_untracked_without_touching_index_or_objects
    prepare_mixed_worktree
    index = File.binread(File.join(@root, '.git/index'))
    objects = git('count-objects', '-v').lines.first
    tree = Shaka::Evidence::CandidateTree.capture(root: @root)

    assert_isolated_capture(tree, index, objects)
    assert_matches_git_tree(tree)
  end

  def test_linked_worktree_capture_preserves_its_index_and_common_objects
    Dir.mktmpdir('shaka-linked-tree') do |parent|
      linked = File.join(parent, 'checkout')
      git('worktree', 'add', '--quiet', '--detach', linked, 'HEAD')
      assert_linked_capture_isolated(linked)
    ensure
      git('worktree', 'remove', '--force', linked) if File.exist?(File.join(linked, '.git'))
    end
  end

  def test_sparse_checkout_preserves_absent_committed_paths
    FileUtils.mkdir_p(File.join(@root, 'included'))
    FileUtils.mkdir_p(File.join(@root, 'omitted'))
    File.write(File.join(@root, 'included/file'), 'one')
    File.write(File.join(@root, 'omitted/file'), 'two')
    git('add', '-A')
    git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'sparse files')
    git('sparse-checkout', 'init', '--cone')
    git('sparse-checkout', 'set', 'included')

    assert_equal git('rev-parse', 'HEAD^{tree}'), Shaka::Evidence::CandidateTree.capture(root: @root)
  end

  private

  def assert_linked_capture_isolated(linked)
    File.write(File.join(linked, 'tracked'), 'linked edit')
    index_path = File.expand_path(git('-C', linked, 'rev-parse', '--git-path', 'index'), linked)
    before_index = File.binread(index_path)
    before_objects = git('count-objects', '-v').lines.first
    tree = Shaka::Evidence::CandidateTree.capture(root: linked)
    assert_match(/\A[0-9a-f]{40}\z/, tree)
    assert_equal before_index, File.binread(index_path)
    assert_equal before_objects, git('count-objects', '-v').lines.first
  end

  def assert_isolated_capture(tree, index, objects)
    assert_match(/\A[0-9a-f]{40}\z/, tree)
    assert_equal index, File.binread(File.join(@root, '.git/index'))
    assert_equal objects, git('count-objects', '-v').lines.first
  end

  def assert_matches_git_tree(tree)
    git('add', '-A')
    assert_equal tree, git('write-tree')
    refute_includes git('ls-tree', '-r', '--name-only', tree), 'ignored'
  end

  def prepare_mixed_worktree
    File.write(File.join(@root, 'tracked'), 'unstaged')
    File.write(File.join(@root, 'staged'), 'staged')
    git('add', 'staged')
    File.symlink('tracked', File.join(@root, 'link'))
    File.write(File.join(@root, 'untracked'), 'new')
    File.write(File.join(@root, '.gitignore'), "ignored\n")
    File.write(File.join(@root, 'ignored'), 'ignored')
  end
end
