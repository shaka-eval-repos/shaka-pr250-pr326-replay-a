# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'shaka/repository_config'

# The seam's ordered reviewer preference list and its identity requirements.
class ReviewPolicyTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_names_the_ci_review_jobs_and_the_local_review_agents
    policy = {
      'required' => 'meaningful_changes',
      'ci_review_jobs' => ['claude-review'],
      'local_review_agents' => reviewers
    }
    with_repository('review' => policy) do |root|
      review = Shaka::RepositoryConfig.load(root:).review

      assert_equal ['claude-review'], review.fetch('ci_review_jobs')
      assert_equal 'openai', review.fetch('local_review_agents').first.fetch('provider')
    end
  end

  def test_loads_the_reviewer_preference_list_in_order
    with_repository do |root|
      review = Shaka::RepositoryConfig.load(root:).review
      providers = review.fetch('local_review_agents').map { |entry| entry.fetch('provider') }

      assert_equal 'meaningful_changes', review.fetch('required')
      assert_equal %w[openai anthropic], providers
    end
  end

  def test_requires_each_reviewer_to_name_its_provider
    incomplete = [{ 'model_family' => 'claude' }]
    with_repository('review' => review_policy('local_review_agents' => incomplete)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'missing review.local_review_agents[0] key: provider'
    end
  end

  def test_rejects_an_empty_reviewer_preference_list
    with_repository('review' => review_policy('local_review_agents' => [])) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.local_review_agents must not be empty'
    end
  end

  def test_rejects_a_repeated_reviewer_identity
    twice = reviewers + [reviewers.first]
    with_repository('review' => review_policy('local_review_agents' => twice)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.local_review_agents repeats openai/codex'
    end
  end

  # Comparing joined strings would make "a b"/"c" and "a"/"b c" the same identity.
  def test_keeps_identities_whose_components_join_alike_distinct
    shifted = [{ 'provider' => 'a b', 'model_family' => 'c' },
               { 'provider' => 'a', 'model_family' => 'b c' }]
    with_repository('review' => review_policy('local_review_agents' => shifted)) do |root|
      review = Shaka::RepositoryConfig.load(root:).review
      providers = review.fetch('local_review_agents').map { |entry| entry.fetch('provider') }

      assert_equal ['a b', 'a'], providers
    end
  end

  def test_names_the_entry_behind_an_unknown_reviewer_key
    typo = [reviewers.first, { 'provider' => 'xai', 'model_family' => 'grok', 'draft' => false }]
    with_repository('review' => review_policy('local_review_agents' => typo)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'unknown review.local_review_agents[1] key: draft'
    end
  end

  # `shaka reviewer` strips each component, so a padded value here would never match the
  # identity the agent passes and a contributing family could pass as eligible.
  # Selection folds case, so two spellings of one identity must not both validate.
  def test_rejects_a_repeated_reviewer_identity_differing_only_by_casing
    cased = reviewers + [{ 'provider' => 'OpenAI', 'model_family' => 'Codex' }]
    with_repository('review' => review_policy('local_review_agents' => cased)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.local_review_agents repeats openai/codex'
    end
  end

  def test_rejects_an_identity_component_padded_with_whitespace
    padded = [{ 'provider' => 'bedrock', 'model_family' => 'claude ' }]
    with_repository('review' => review_policy('local_review_agents' => padded)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'model_family must not start or end with whitespace'
    end
  end

  def test_rejects_an_identity_component_containing_a_slash
    slashed = [{ 'provider' => 'openai/foo', 'model_family' => 'codex' }]
    with_repository('review' => review_policy('local_review_agents' => slashed)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, "provider must not contain '/'"
    end
  end

  def test_points_a_retired_flat_field_at_the_reviewer_list
    retired = { 'required' => 'meaningful_changes', 'check' => 'claude-review',
                'model_family' => 'claude', 'provider' => 'anthropic', 'draft' => false }
    with_repository('review' => retired) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.model_family moved into review.local_review_agents'
    end
  end

  def test_keeps_reviewer_preferences_when_no_native_gate_is_required
    with_repository('review' => { 'required' => 'none', 'local_review_agents' => reviewers }) do |root|
      review = Shaka::RepositoryConfig.load(root:).review
      providers = review.fetch('local_review_agents').map { |entry| entry.fetch('provider') }

      assert_equal %w[openai anthropic], providers
    end
  end

  def test_rejects_ci_review_jobs_when_review_is_not_required
    policy = { 'required' => 'none', 'ci_review_jobs' => ['claude-review'] }
    with_repository('review' => policy) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_jobs must be omitted when review.required is none'
    end
  end
end

class RetiredReviewKeyTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_points_the_old_ci_agent_key_at_job_names
    with_repository('review' => { 'required' => 'meaningful_changes',
                                  'ci_review_agents' => ['claude-review'] }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_agents moved to review.ci_review_jobs'
    end
  end

  def test_rejects_a_retired_check_key
    with_repository('review' => { 'required' => 'meaningful_changes', 'check' => 'claude-review' }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.check moved to review.ci_review_jobs'
    end
  end

  def test_rejects_a_retired_local_reviewers_key
    with_repository('review' => { 'required' => 'meaningful_changes', 'local_reviewers' => reviewers }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.local_reviewers moved to review.local_review_agents'
    end
  end

  def test_rejects_a_retired_reviewers_key
    with_repository('review' => { 'required' => 'meaningful_changes', 'reviewers' => reviewers }) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.reviewers moved to review.local_review_agents'
    end
  end
end

class CiReviewJobsTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_rejects_a_ci_review_job_name_that_is_not_a_list
    with_repository('review' => review_policy('ci_review_jobs' => 'claude-review')) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_jobs must be a list of CI job names'
    end
  end

  def test_rejects_an_empty_ci_review_job_list
    with_repository('review' => review_policy('ci_review_jobs' => [])) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_jobs must not be empty'
    end
  end

  def test_rejects_a_blank_ci_review_job_name
    with_repository('review' => review_policy('ci_review_jobs' => [''])) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_jobs[0] must be a non-empty string'
    end
  end

  def test_rejects_a_repeated_ci_review_job_name_differing_only_by_casing
    names = %w[Claude-Review claude-review]
    with_repository('review' => review_policy('ci_review_jobs' => names)) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.ci_review_jobs repeats claude-review'
    end
  end
end
