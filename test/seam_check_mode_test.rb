# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'seam_check_helpers'
require 'shaka/seam'

class SeamCheckModeTest < Minitest::Test
  include SeamCheckHelpers

  CheckReport = Shaka::Seam::CheckReport
  COMMAND = SeamCheckHelpers::COMMAND

  def test_help_documents_local_mode
    output, error, status = Open3.capture3(COMMAND, 'seam', 'check', '--help')

    assert_predicate status, :success?, error
    assert_includes output, '--local'
    assert_includes output, '--ref'
  end

  def test_local_check_labels_candidate_output_and_grants_no_authority
    with_repository do |root|
      payload, error, status = capture_check(root, '--local')

      assert_predicate status, :success?, error
      refute_includes error, CheckReport::IMPLICIT_DIAGNOSTIC
      assert_local_candidate payload
      assert_equal 'auto', payload.dig('merge', 'preference')
    end
  end

  def test_omitted_mode_warns_and_still_labels_candidate_output
    with_repository do |root|
      payload, error, status = capture_check(root)

      assert_predicate status, :success?, error
      assert_includes error, CheckReport::IMPLICIT_DIAGNOSTIC
      assert_local_candidate payload
    end
  end

  def test_ref_check_labels_trusted_policy_and_still_grants_no_merge_authority
    with_repository do |root|
      commit_repository(root)
      payload, error, status = capture_check(root, '--ref', 'HEAD')

      assert_predicate status, :success?, error
      refute_includes error, CheckReport::IMPLICIT_DIAGNOSTIC
      assert_trusted_policy payload
    end
  end

  def test_local_cannot_be_combined_with_ref
    with_repository do |root|
      _payload, error, status = capture_check(root, '--local', '--ref', 'HEAD')

      refute_predicate status, :success?
      assert_includes error, '--local cannot be combined with --ref'
    end
  end

  def test_required_check_does_not_apply_to_check
    with_repository do |root|
      _payload, error, status = capture_check(root, '--local', '--required-check', 'checks')

      refute_predicate status, :success?
      assert_includes error, 'init options do not apply to check'
    end
  end

  def test_local_does_not_apply_to_init
    Dir.mktmpdir('shaka-seam-init') do |root|
      _output, error, status = Open3.capture3(COMMAND, 'seam', 'init', '--root', root, '--local')

      refute_predicate status, :success?
      assert_includes error, '--local does not apply to init'
    end
  end

  private

  def assert_local_candidate(payload)
    validation = payload.fetch('validation')
    assert_equal CheckReport::LOCAL_MODE, validation.fetch('mode')
    assert_false validation.fetch('grants_policy')
    assert_false validation.fetch('grants_merge_authority')
    refute validation.key?('sha')
  end

  def assert_trusted_policy(payload)
    validation = payload.fetch('validation')
    assert_equal CheckReport::TRUSTED_MODE, validation.fetch('mode')
    assert_true validation.fetch('grants_policy')
    assert_false validation.fetch('grants_merge_authority')
    assert_equal 'HEAD', validation.fetch('ref')
    assert_match(/\A[0-9a-f]{40}\z/, validation.fetch('sha'))
  end
end
