# frozen_string_literal: true

require_relative 'handoff_helper'

class HandoffTest < Minitest::Test
  include HandoffHarness

  def test_a_labeled_current_pr_owes_nothing
    result = handoff

    assert_empty result.fetch('owed')
    assert_equal 'status', result.keys.first
    assert_equal "PR #42 OPEN head #{HEAD[0, 7]} · awaiting-resume · required checks 1 pass · " \
                 "walkthrough #{HEAD[0, 7]} · WIP #{HEAD[0, 7]}", result['status']
  end

  def test_an_open_pr_without_an_attention_label_owes_one
    result = handoff(labels: ['bug'])

    assert_equal 'no awaiting label', result['status'][/no awaiting label/]
    assert(result['owed'].any? { |item| item.include?('attention') })
  end

  def test_a_session_something_will_wake_needs_no_label
    result = handoff(labels: [], woken_by: 'background watcher')

    assert_empty result['owed']
    assert_includes result['status'], 'woken by background watcher'
  end

  def test_a_blank_wake_source_is_refused
    error = assert_raises(Shaka::Error) { handoff(labels: [], woken_by: '  ') }

    assert_includes error.message, '--woken-by needs a name'
  end

  def test_a_wake_source_does_not_excuse_a_leftover_label
    result = handoff(labels: ['awaiting-resume'], woken_by: 'background watcher')

    assert(result['owed'].any? { |item| item.include?('Remove awaiting-resume') })
  end

  def test_merge_approval_without_a_walkthrough_is_owed
    result = handoff(labels: ['awaiting-merge-approval'], reviews: [])

    assert(result['owed'].any? { |item| item.include?('Publish a walkthrough') })
  end

  def test_a_check_whose_state_and_bucket_disagree_is_not_passing
    result = handoff(labels: ['awaiting-merge-approval'],
                     checks: [{ 'name' => 'validate', 'state' => 'FAILURE', 'bucket' => 'pass' }])

    assert(result['owed'].any? { |item| item.include?('not all passing') })
  end

  def test_a_copied_walkthrough_from_another_account_is_ignored
    result = handoff(reviews: [walkthrough(HEAD), walkthrough(OLD, author: 'outsider')])

    assert_empty result['owed']
  end

  def test_two_attention_labels_are_owed_as_one_decision
    result = handoff(labels: %w[awaiting-answer awaiting-resume])

    assert(result['owed'].any? { |item| item.include?('exactly one') })
  end

  def test_merge_approval_while_required_checks_are_pending_is_owed
    %w[awaiting-merge-approval Awaiting-Merge-Approval].each do |label|
      result = handoff(labels: [label], checks: [check('pending')])

      assert(result['owed'].any? { |item| item.include?('awaiting-merge-approval') }, label)
    end
  end

  def test_a_moved_head_is_owed
    result = handoff(expected: OLD)

    assert(result['owed'].any? { |item| item.include?('head moved') })
  end

  def test_a_head_that_moves_during_the_reads_is_owed
    result = handoff(final_head: OLD)

    assert(result['owed'].any? { |item| item.include?('while handoff read it') })
  end

  def test_a_cleared_revision_cell_counts_as_missing
    cleared = description.sub(/^\| Revision \| .* \|$/, '| Revision |  |')

    assert(handoff(body: cleared).fetch('owed').any? { |item| item.include?('WIP Details is missing') })
  end

  def test_a_missing_or_stale_wip_note_is_owed
    assert(handoff(body: 'no note').fetch('owed').any? { |item| item.include?('WIP Details is missing') })

    stale_heads = [OLD, OLD[0, 7], 'UNKNOWN'].map { |head| "fix/#{HEAD} @ #{head}" }
    ["feature @ #{OLD}", *stale_heads].each do |revision|
      stale = handoff(body: description(WIP.merge('revision' => revision)))
      assert(stale['owed'].any? { |item| item.include?('WIP Details names') }, revision)
    end
  end

  def test_a_walkthrough_for_an_older_head_is_owed_but_a_missing_one_is_only_noted
    assert(handoff(reviews: [walkthrough(OLD)]).fetch('owed').any? { |item| item.include?('walkthrough') })

    missing = handoff(reviews: [])
    assert_empty missing['owed']
    assert(missing['notes'].any? { |item| item.include?('No walkthrough') })
  end

  def test_the_latest_walkthrough_wins
    result = handoff(reviews: [walkthrough(OLD), walkthrough(HEAD)])

    assert_empty result['owed']
  end

  def test_a_closed_pr_owes_nothing_and_reads_no_labels
    result = handoff(state: 'MERGED', labels: nil, reviews: nil)

    assert_empty result['owed']
    assert_equal "PR #42 MERGED head #{HEAD[0, 7]}", result['status']
  end

  def test_owed_work_exits_with_its_own_status
    assert_equal 0, Shaka::Handoff.exit_status(handoff)
    assert_equal Shaka::Handoff::OWED_EXIT, Shaka::Handoff.exit_status(handoff(labels: []))
  end

  def test_the_head_is_optional_for_a_resumed_session
    result = handoff(expected: nil)

    assert_empty result['owed']
  end
end

# Handoff reads only evidence Shaka controls: commit-bound reviews and its own description region.
class HandoffEvidenceTest < Minitest::Test
  include HandoffHarness

  def test_a_walkthrough_whose_footer_disagrees_with_its_commit_does_not_count
    result = handoff(reviews: [walkthrough(HEAD, commit: OLD)])

    assert(result['notes'].any? { |item| item.include?('No walkthrough') })
  end

  def test_a_wip_note_outside_the_managed_region_does_not_count
    body = "#{HandoffFixtures.rendered}\n\n#{Shaka::Publishing::OPEN_MARK}\nsummary#{Shaka::Publishing::CLOSE_MARK}"

    assert(handoff(body:).fetch('owed').any? { |item| item.include?('WIP Details is missing') })
  end

  def test_reversed_markers_hold_no_managed_region
    marks = [Shaka::Publishing::CLOSE_MARK, Shaka::Publishing::OPEN_MARK]
    body = "#{marks.join("\n")}\n#{HandoffFixtures.rendered}"

    assert(handoff(body:).fetch('owed').any? { |item| item.include?('WIP Details is missing') })
  end
end

class HandoffCliTest < Minitest::Test
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  # The flag is refused before any GitHub client exists, so this runs offline.
  def test_handoff_without_a_trusted_ref_is_refused
    _output, error, status = Open3.capture3(COMMAND, 'handoff', 'owner/repo', '1')

    refute_predicate status, :success?
    assert_includes error, 'handoff requires --ref'
  end

  def test_woken_by_is_refused_outside_handoff
    _output, error, status = Open3.capture3(COMMAND, 'attention', 'owner/repo', '1', '--state', 'none',
                                            '--woken-by', 'watcher')

    refute_predicate status, :success?
    assert_includes error, '--woken-by is only for handoff'
  end
end
