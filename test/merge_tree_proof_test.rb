# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'shaka/merge_tree_proof'

# A repository where a feature branch edits the first of two identical blocks and main moves on.
module MergeTreeProofRepository
  BLOCK = "value = 1\n"

  def setup
    @root = Dir.mktmpdir('shaka-merge-tree-')
    git('init', '--quiet', '--initial-branch=main')
    write('app.rb', "#{BLOCK}middle\n#{BLOCK}")
    write('run.sh', "echo run\n", mode: 0o755)
    write('footer.txt', "footer\n")
    commit('base')
    branch_and_move_base
  end

  # The feature branch edits the first block; main then changes an unrelated file.
  def branch_and_move_base
    git('switch', '--quiet', '-c', 'feature')
    write('app.rb', "value = 2\nmiddle\n#{BLOCK}")
    @reviewed = commit('reviewed change')
    git('switch', '--quiet', 'main')
    write('footer.txt', "new footer\n")
    @new_base = commit('base moves on')
  end

  def teardown = FileUtils.remove_entry(@root)

  def git(*args)
    output, error, status = Open3.capture3('git', '-C', @root, '-c', 'user.name=Test',
                                           '-c', 'user.email=test@example.com', *args)
    raise "git #{args.join(' ')} failed: #{error}" unless status.success?

    output.strip
  end

  def write(name, text, mode: 0o644)
    path = File.join(@root, name)
    File.write(path, text)
    File.chmod(mode, path)
  end

  def commit(message)
    git('add', '-A')
    git('commit', '--quiet', '-m', message)
    git('rev-parse', 'HEAD')
  end

  def rebased_head
    git('switch', '--quiet', 'feature')
    git('rebase', '--quiet', 'main')
    git('rev-parse', 'HEAD')
  end

  def proof(head) = Shaka::MergeTreeProof.new(@root).problem(reviewed: @reviewed, base: @new_base, head:)
end

# A review survives only a conflict-free update from the base.
class MergeTreeProofTest < Minitest::Test
  include MergeTreeProofRepository

  def test_a_clean_rebase_matches
    assert_nil proof(rebased_head)
  end

  def test_merging_the_base_into_the_branch_matches
    git('switch', '--quiet', 'feature')
    git('merge', '--quiet', '--no-edit', 'main')

    assert_nil proof(git('rev-parse', 'HEAD'))
  end

  def test_moving_the_edit_to_an_identical_block_does_not_match
    rebased_head
    write('app.rb', "#{BLOCK}middle\nvalue = 2\n")

    assert_match(/differs from a clean merge/, proof(commit('move the edit')))
  end

  def test_removing_an_executable_bit_does_not_match
    rebased_head
    File.chmod(0o644, File.join(@root, 'run.sh'))

    assert_match(/differs from a clean merge/, proof(commit('drop the executable bit')))
  end

  def test_a_conflicting_update_does_not_match
    git('switch', '--quiet', 'main')
    write('app.rb', "value = 3\nmiddle\n#{BLOCK}")
    @new_base = commit('conflicting base change')

    assert_match(/does not merge cleanly/, proof(@reviewed))
  end

  def test_a_missing_commit_cannot_be_proven
    assert_match(/not available locally/, proof('0' * 40))
  end

  def test_a_directory_outside_git_cannot_be_proven
    Dir.mktmpdir do |outside|
      problem = Shaka::MergeTreeProof.new(outside).problem(reviewed: @reviewed, base: @new_base, head: @reviewed)

      assert_match(/not available locally/, problem)
    end
  end
end

# The proof must run only Git's built-in merge and leave the checkout repository untouched.
class MergeTreeProofIsolationTest < Minitest::Test
  include MergeTreeProofRepository

  # The branch picks merge drivers through .gitattributes; the proof must never run one.
  def test_a_configured_merge_driver_never_runs
    marker = File.join(@root, 'driver-ran')
    select_driver_on_branch("touch #{marker}; false")

    proof(@reviewed)

    refute_path_exists marker
  end

  # Leaves the branch checked out, as a candidate checkout would be, with both sides editing app.rb.
  def select_driver_on_branch(command)
    git('config', 'merge.evil.driver', command)
    git('switch', '--quiet', 'feature')
    write('.gitattributes', "app.rb merge=evil\n")
    @reviewed = commit('select the driver')
    git('switch', '--quiet', 'main')
    write('app.rb', "#{BLOCK}middle\nvalue = 9\n")
    @new_base = commit('base edits the same file')
    git('switch', '--quiet', 'feature')
  end

  # merge.default picks a driver even when no attribute names one.
  def test_a_default_merge_driver_never_runs
    marker = File.join(@root, 'default-driver-ran')
    git('config', 'merge.default', 'evil')
    select_driver_on_branch("touch #{marker}; true")
    File.delete(File.join(@root, '.gitattributes'))
    File.write(File.join(@root, '.git', 'info', 'attributes'), "* merge=evil\n")

    proof(@reviewed)

    refute_path_exists marker
  end

  # The unrebased branch head differs from the merge, so the merged tree is new.
  # Configuration can also arrive through the environment of the process that runs merge.
  def test_a_driver_from_environment_configuration_never_runs
    marker = File.join(@root, 'environment-driver-ran')
    select_driver_on_branch('true')
    File.delete(File.join(@root, '.gitattributes'))
    settings = { 'GIT_CONFIG_COUNT' => '2', 'GIT_CONFIG_KEY_0' => 'merge.default', 'GIT_CONFIG_VALUE_0' => 'env',
                 'GIT_CONFIG_KEY_1' => 'merge.env.driver', 'GIT_CONFIG_VALUE_1' => "touch #{marker}; true" }
    with_environment(settings) { proof(@reviewed) }

    refute_path_exists marker
  end

  def with_environment(settings)
    saved = settings.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    settings.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def test_an_old_git_is_reported_as_unsupported
    proof = Shaka::MergeTreeProof.new(@root)
    def proof.git_version = 'git version 2.40.1'

    assert_match(/Git 2\.41 or later/, proof.problem(reviewed: @reviewed, base: @new_base, head: @reviewed))
  end

  def test_the_proof_writes_nothing_into_the_checkout_repository
    before = git('count-objects', '-v')

    assert_match(/differs from a clean merge/, proof(@reviewed))
    assert_equal before, git('count-objects', '-v')
  end

  def test_a_git_that_cannot_start_leaves_the_proof_unavailable
    proof = Shaka::MergeTreeProof.new(@root)
    def proof.git(*) = raise(Errno::ENOENT, 'git')

    assert_match(/not available locally/, proof.problem(reviewed: @reviewed, base: @new_base, head: @reviewed))
  end
end
