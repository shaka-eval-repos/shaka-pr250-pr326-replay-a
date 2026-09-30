# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'
require 'rbconfig'

class CliOpeningUnsupportedTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Pull requests explain the outcome first.'

  def test_listed_unsupported_reviewer_falls_back_with_a_clear_reason
    review = review_policy('local_review_agents' => [{ 'provider' => 'foo', 'model_family' => 'bar' }])
    with_repository('opening_check' => { 'external_enabled' => true }, 'review' => review) do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        output, error, status = run_description(dir, root:, reviewer: 'foo/bar')
        assert_predicate status, :success?, error
        assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
        assert_includes JSON.parse(output).dig('opening', 'reason'), 'Unsupported local reviewer'
      end
    end
  end
end
