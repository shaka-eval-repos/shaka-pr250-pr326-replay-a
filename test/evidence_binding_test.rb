# frozen_string_literal: true

require_relative 'evidence_fixture'

class EvidenceBindingTest < Minitest::Test
  include EvidenceFixture

  def test_uncommitted_result_binds_only_after_matching_commit
    with_checkout do |root, ref|
      File.write(File.join(root, 'feature'), 'first')
      result = run_check(root, ref)
      assert_equal 'completed', result.fetch('status')
      binding = bind(root, ref, commit_feature(root), result)
      assert_equal 'bound', binding.fetch('status')
      assert_equal result.fetch('tested_tree'), binding.fetch('commit_tree')
      assert_equal result, binding.fetch('original')
    end
  end

  def test_uncommitted_file_left_out_of_commit_supersedes_result
    with_checkout do |root, ref|
      File.write(File.join(root, 'feature'), 'first')
      File.write(File.join(root, 'unrelated'), 'left dirty')
      result = run_check(root, ref)
      binding = bind(root, ref, commit_feature(root), result)
      assert_equal 'superseded', binding.fetch('status')
      assert_includes binding.fetch('reasons'), 'candidate tree differs from tested tree'
      assert_equal result.fetch('tested_tree'), binding.fetch('original').fetch('tested_tree')
    end
  end

  def test_changed_command_input_supersedes_bound_result
    with_checkout do |root, ref|
      result = run_check(root, ref)
      File.write(File.join(root, '.agents/bin/test'), "#!/bin/sh\nexit 1\n")
      binding = bind(root, ref, ref, result)

      assert_equal 'superseded', binding.fetch('status')
      assert_includes binding.fetch('changed_settings_components'), 'files'
    end
  end

  def test_missing_result_requires_rerun
    with_checkout do |root, ref|
      binding = bind(root, ref, ref, { 'kind' => 'validation' })
      assert_equal 'superseded', binding.fetch('status')
      assert_includes binding.fetch('reasons'), 'missing tested tree'
      assert_includes binding.fetch('reasons'), 'missing or invalid settings identity'
      result = run_check(root, ref)
      result['command'] = 'validate'
      assert_includes bind(root, ref, ref, result).fetch('reasons'), 'validation command differs from settings command'
    end
  end

  def test_changed_inputs_during_execution_invalidate_result
    with_checkout do |root, ref|
      File.write(File.join(root, '.agents/bin/test'), "#!/bin/sh\necho changed > changed\n")
      result = run_check(root, ref, expected_exit: 1)
      assert_raises(Shaka::Error) { Shaka::Evidence::Result.commit_tree(root, result.fetch('tested_tree')) }
      assert_equal 'not_completed', result.fetch('status')
      assert result.fetch('inputs_changed')
      refute_equal result.fetch('tested_tree'), result.fetch('tree_after')
    end
  end

  private

  def commit_feature(root)
    git(root, 'add', 'feature')
    commit(root)
    git(root, 'rev-parse', 'HEAD')
  end
end
