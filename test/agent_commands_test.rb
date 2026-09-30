# frozen_string_literal: true

require_relative 'test_helper'
require 'bundler'

class AgentCommandsTest < Minitest::Test
  TEST_COMMAND = File.expand_path('../.agents/bin/test', __dir__)

  def test_focused_tests_override_an_inherited_bundle
    environment = { 'BUNDLE_GEMFILE' => '/missing/shaka/Gemfile', 'RUBYOPT' => '-rbundler/setup' }
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e(environment, TEST_COMMAND, 'test/recommendation_test.rb')
    end

    assert_predicate status, :success?, output
  end

  def test_focused_tests_select_the_repository_bundle_from_an_outside_directory
    Dir.mktmpdir('shaka-outside-bundle') do |outside_root|
      File.write(File.join(outside_root, 'Gemfile'), "gem 'missing-outside-bundle-gem'\n")

      output, status = Bundler.with_unbundled_env do
        Open3.capture2e(TEST_COMMAND, 'test/recommendation_test.rb', chdir: outside_root)
      end

      assert_predicate status, :success?, output
    end
  end
end
