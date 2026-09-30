# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'yaml'
require 'shaka/merge_limits'
require 'shaka/repository_config'

class MergeLimitsTest < Minitest::Test
  include RepositoryConfigTestHelpers

  INVALID = {
    [] => 'merge.limits must be a mapping',
    { 'max_changed_bytes' => 5 } => 'unknown merge.limits key: max_changed_bytes',
    { 'max_commits' => 0 } => 'merge.limits.max_commits must be a positive integer',
    { 'max_changed_files' => '29' } => 'merge.limits.max_changed_files must be a positive integer',
    { 'max_changed_lines' => 9.5 } => 'merge.limits.max_changed_lines must be a positive integer'
  }.freeze

  def test_limits_default_to_the_built_in_maxima
    with_repository do |root|
      config = Shaka::RepositoryConfig.load(root:)

      assert_equal Shaka::MergeLimits::DEFAULTS, config.merge.fetch('limits')
      assert_equal Shaka::MergeLimits::DEFAULTS, config.to_h.fetch('merge').fetch('limits')
    end
  end

  def test_a_repository_can_change_one_limit
    with_repository('merge' => { 'preference' => 'auto', 'limits' => { 'max_commits' => 20 } }) do |root|
      limits = Shaka::RepositoryConfig.load(root:).merge.fetch('limits')

      assert_equal Shaka::MergeLimits::DEFAULTS.merge('max_commits' => 20), limits
    end
  end

  def test_rejects_invalid_limits
    INVALID.each do |limits, message|
      with_repository('merge' => { 'preference' => 'auto', 'limits' => limits }) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

        assert_includes error.message, message
      end
    end
  end

  def test_reads_limits_from_a_trusted_ref_not_the_candidate_file
    with_repository('merge' => { 'preference' => 'auto', 'limits' => { 'max_commits' => 3 } }) do |root|
      commit_repository(root)
      loosen_candidate_limits(root)

      assert_equal 3, Shaka::MergeLimits.from_ref(root:, ref: 'HEAD').to_h.fetch('max_commits')
      assert_equal Shaka::MergeLimits::DEFAULTS, Shaka::MergeLimits.from_ref(root:, ref: nil).to_h
    end
  end

  private

  def commit_repository(root)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    system('git', '-C', root, 'add', '.', exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'trusted', exception: true)
  end

  def loosen_candidate_limits(root)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.load_file(path)
    data['merge']['limits'] = { 'max_commits' => 500 }
    File.write(path, YAML.dump(data))
  end
end
