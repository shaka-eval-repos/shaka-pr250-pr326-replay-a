# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/required_checks'

class RequiredChecksTest < Minitest::Test
  Client = Struct.new(:native, :head, :configured) do
    def required_checks = native
    def checks = head
    def configured_required_checks = configured || []
  end

  PASS = { 'name' => 'checks', 'state' => 'SUCCESS', 'bucket' => 'pass' }.freeze

  def test_native_required_checks_win_over_the_seam_list
    native = [{ 'name' => 'validate', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    result = Shaka::RequiredChecks.new(Client.new(native, [PASS]), seam_names: ['checks']).call

    assert_equal({ 'source' => 'github', 'checks' => native }, result)
  end

  def test_seam_list_applies_when_github_enforces_no_checks
    other = { 'name' => 'lint', 'state' => 'FAILURE', 'bucket' => 'fail' }
    result = Shaka::RequiredChecks.new(Client.new([], [other, PASS]), seam_names: ['checks']).call

    assert_equal({ 'source' => 'seam', 'checks' => [PASS] }, result)
  end

  # An unreported native requirement leaves `gh pr checks --required` empty; it must block, not vanish.
  def test_configured_native_requirements_that_have_not_reported_are_missing
    missing = { 'name' => 'validate', 'state' => 'MISSING', 'bucket' => 'missing' }
    [['checks'], nil].each do |seam_names|
      result = Shaka::RequiredChecks.new(Client.new([], [PASS], ['validate']), seam_names:).call

      assert_equal({ 'source' => 'github', 'checks' => [missing] }, result)
    end
  end

  def test_a_seam_check_absent_from_the_head_is_reported_missing
    result = Shaka::RequiredChecks.new(Client.new([], [PASS]), seam_names: %w[checks deploy-preview]).call

    missing = { 'name' => 'deploy-preview', 'state' => 'MISSING', 'bucket' => 'missing' }
    assert_equal [PASS, missing], result.fetch('checks')
  end

  def test_without_a_seam_list_the_empty_native_set_stands
    result = Shaka::RequiredChecks.new(Client.new([], [PASS])).call

    assert_equal({ 'source' => 'github', 'checks' => [] }, result)
  end
end
