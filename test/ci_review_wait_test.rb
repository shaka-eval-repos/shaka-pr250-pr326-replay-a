# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'yaml'
require 'shaka/repository_config'
require 'shaka/ci_review_wait'
require 'shaka/trusted_config_source'

class CiReviewWaitTest < Minitest::Test
  def test_omitted_wait_is_one
    assert_equal 'one', Shaka::CiReviewWait.normalize(nil)
  end

  def test_rejects_an_unknown_wait
    error = assert_raises(Shaka::Error) { Shaka::CiReviewWait.normalize('fast') }

    assert_includes error.message, 'review.ci_review_wait must be none, one, or all'
  end

  def test_an_all_trusted_seam_cannot_be_weakened_to_one
    assert_equal 'all', Shaka::CiReviewWait.effective(seam: 'all', override: 'one')
  end

  def test_a_this_task_override_can_raise_one_to_all
    assert_equal 'all', Shaka::CiReviewWait.effective(seam: 'one', override: 'all')
  end

  def test_an_explicit_task_wait_applies_without_a_trusted_setting
    assert_equal 'none', Shaka::CiReviewWait.effective(seam: nil, override: 'none')
    assert_equal 'one', Shaka::CiReviewWait.effective(seam: nil)
  end

  def test_trusted_wait_is_a_minimum_for_every_override
    values = %w[none one all]
    values.product(values).each do |seam, override|
      expected = [seam, override].max_by { |value| values.index(value) }
      assert_equal expected, Shaka::CiReviewWait.effective(seam:, override:)
    end
  end

  def test_none_and_one_allow_optional_checks_in_both_queue_modes
    %w[none one].product([true, false]).each do |wait, queue|
      assert_includes Shaka::CiReviewWait.allowed_merge_states(wait, queue), 'UNSTABLE'
    end
  end

  def test_explicit_one_stays_one_even_if_the_product_default_changes
    original = Shaka::CiReviewWait::DEFAULT
    Shaka::CiReviewWait.send(:remove_const, :DEFAULT)
    Shaka::CiReviewWait.const_set(:DEFAULT, 'all')

    assert_equal 'one', Shaka::CiReviewWait.effective(seam: 'one', override: nil)
  ensure
    Shaka::CiReviewWait.send(:remove_const, :DEFAULT)
    Shaka::CiReviewWait.const_set(:DEFAULT, original)
  end

  def test_all_merge_states_do_not_follow_the_default_constant
    assert_equal %w[CLEAN], Shaka::CiReviewWait.allowed_merge_states('all', false)
    assert_includes Shaka::CiReviewWait.allowed_merge_states('one', false), 'UNSTABLE'
  end
end

class CiReviewWaitSeamTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_defaults_omitted_ci_review_wait_to_one
    with_repository('review' => review_policy) do |root|
      config = Shaka::RepositoryConfig.load(root:)

      assert_equal 'one', config.review.fetch('ci_review_wait')
      assert_equal 'one', config.to_h.fetch('review').fetch('ci_review_wait')
    end
  end

  def test_loads_an_explicit_all_ci_review_wait
    with_repository('review' => review_policy('ci_review_wait' => 'all')) do |root|
      assert_equal 'all', Shaka::RepositoryConfig.load(root:).review.fetch('ci_review_wait')
    end
  end

  def test_rejects_an_unknown_ci_review_wait
    with_repository('review' => review_policy('ci_review_wait' => 'false')) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_wait must be none, one, or all'
    end
  end

  def test_loads_each_named_wait_and_rejects_booleans
    %w[none one all].each do |wait|
      with_repository('review' => review_policy('ci_review_wait' => wait)) do |root|
        assert_equal wait, Shaka::RepositoryConfig.load(root:).review.fetch('ci_review_wait')
      end
    end
    [true, false].each do |wait|
      with_repository('review' => review_policy('ci_review_wait' => wait)) do |root|
        assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }
      end
    end
  end

  def test_rejects_a_null_ci_review_wait
    with_repository('review' => review_policy('ci_review_wait' => nil)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_wait must be none, one, or all'
    end
  end

  def test_reads_merge_policy_from_a_trusted_ref_not_the_candidate_file
    trusted = { 'review' => review_policy('ci_review_wait' => 'all'),
                'merge' => merge_policy.merge('required_checks' => ['checks']) }
    with_repository(trusted) do |root|
      commit_repository(root)
      weaken_candidate_policy(root)
      seam = Shaka::TrustedConfigSource.from_ref(root:, ref: 'HEAD')

      assert_equal 'all', seam.review.fetch('ci_review_wait')
      assert_equal ['checks'], seam.merge.fetch('required_checks')
      assert_nil Shaka::TrustedConfigSource.from_ref(root:, ref: nil)
    end
  end

  def test_legacy_key_requires_migration
    with_repository('review' => review_policy('pace' => 'thorough')) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_wait'
    end
  end

  def commit_repository(root)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    system('git', '-C', root, 'add', '.', exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'trusted', exception: true)
  end

  def weaken_candidate_policy(root)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.load_file(path)
    data['review']['ci_review_wait'] = 'none'
    data['merge'].delete('required_checks')
    File.write(path, YAML.dump(data))
  end
end
