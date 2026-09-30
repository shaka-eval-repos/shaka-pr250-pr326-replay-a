# frozen_string_literal: true

require_relative 'reviewer_command_test'
require 'shaka/reviewer_selection'

class MultipleReviewerSelectionTest < ReviewerCommandTest
  def test_configured_count_and_override_use_trusted_settings
    with_repository do |root|
      set_count(root, 3)
      commit_repository(root)
      set_count(root, 1)
      result = reviewer(root, '--ref', 'HEAD', '--implementer', 'anthropic/claude')
      assert_equal %w[openai/codex anthropic/claude xai/grok], result.fetch('reviewers')
      assert_override(root)
    end
  end

  def test_rejects_invalid_configuration_counts
    [0, -1, '2', 1.5, true, nil].each do |count|
      with_repository do |root|
        set_count(root, count)
        _, error, status = Open3.capture3(COMMAND, 'reviewer', '--root', root, '--implementer', 'openai/codex')
        refute_predicate status, :success?
        assert_includes error, 'positive integer'
      end
    end
  end

  def test_rejects_invalid_overrides
    with_repository do |root|
      %w[0 -1 1.5 two +2 02].each do |count|
        _, error, status = Open3.capture3(COMMAND, 'reviewer', '--root', root,
                                          '--implementer', 'openai/codex', '--count', count)
        refute_predicate status, :success?
        assert_includes error, 'positive integer'
      end
    end
  end

  def test_unavailable_and_duplicate_identities_do_not_fill_the_batch
    roster = %w[anthropic/claude OpenAI/Codex openai/codex xai/grok].map do |id|
      Shaka::ReviewerSelection.parse(id)
    end
    result = Shaka::ReviewerSelection.new(reviewers: roster, count: 9,
                                          implementers: [Shaka::ReviewerSelection.parse('anthropic/claude')],
                                          unavailable: [Shaka::ReviewerSelection.parse('xai/grok')]).call
    assert_equal %w[OpenAI/Codex anthropic/claude], result.fetch('reviewers')
    assert_equal 'different_provider', result.fetch('outcome')
    assert_equal 'OpenAI/Codex', result.fetch('reviewer')
  end

  def test_fallback_stays_one_fresh_host_context
    identity = Shaka::ReviewerSelection.parse('openai/codex')
    result = Shaka::ReviewerSelection.new(reviewers: [identity], implementers: [identity],
                                          unavailable: [identity], count: 3).call
    assert_equal ['openai/codex'], result.fetch('reviewers')
    assert_equal 'same_model', result.fetch('outcome')
  end

  private

  def set_count(root, count)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.safe_load_file(path)
    data['review']['local_review_count'] = count
    File.write(path, YAML.dump(data))
  end

  def assert_override(root)
    result = reviewer(root, '--ref', 'HEAD', '--implementer', 'anthropic/claude', '--count', '2')
    assert_equal %w[openai/codex anthropic/claude], result.fetch('reviewers')
  end
end
