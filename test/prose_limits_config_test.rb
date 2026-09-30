# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'yaml'
require 'shaka/prose_limits'
require 'shaka/repository_config'

# Maintainers tune prose limits in the trusted repository contract.
class ProseLimitsConfigTest < Minitest::Test
  include RepositoryConfigTestHelpers

  INVALID = {
    [] => 'prose_limits must be a mapping',
    { 'max_page_words' => 5 } => 'unknown prose_limits key: max_page_words',
    { 'max_sentence_words' => 0 } => 'prose_limits.max_sentence_words must be a positive integer',
    { 'max_paragraph_words' => '100' } => 'prose_limits.max_paragraph_words must be a positive integer'
  }.freeze

  def test_limits_default_and_a_repository_can_change_one
    with_repository do |root|
      assert_equal Shaka::ProseLimits::DEFAULTS, Shaka::RepositoryConfig.load(root:).to_h.fetch('prose_limits')
    end
    with_repository('prose_limits' => { 'max_sentence_words' => 50 }) do |root|
      limits = Shaka::RepositoryConfig.load(root:).prose_limits

      assert_equal Shaka::ProseLimits::DEFAULTS.merge('max_sentence_words' => 50), limits
      Shaka::ProseLimits.new(limits).verify!(sentence(50), kind: :walkthrough, changed_lines: 50)
    end
  end

  def test_rejects_invalid_limits
    INVALID.each do |limits, message|
      with_repository('prose_limits' => limits) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

        assert_includes error.message, message
      end
    end
  end

  def test_reads_limits_from_a_trusted_ref_not_the_candidate_file
    with_repository('prose_limits' => { 'max_sentence_words' => 30 }) do |root|
      commit_repository(root)
      loosen_candidate_limits(root)

      assert_equal 30, Shaka::ProseLimits.from_ref(root:, ref: 'HEAD').to_h.fetch('max_sentence_words')
      assert_equal Shaka::ProseLimits::DEFAULTS, Shaka::ProseLimits.from_ref(root:, ref: nil).to_h
    end
  end

  private

  def sentence(words) = "Alpha #{Array.new(words - 2, 'word').join(' ')} end."

  def commit_repository(root)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    system('git', '-C', root, 'add', '.', exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'trusted', exception: true)
  end

  def loosen_candidate_limits(root)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.load_file(path)
    data['prose_limits'] = { 'max_sentence_words' => 500 }
    File.write(path, YAML.dump(data))
  end
end
