# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/merge'

module MergeFixtures
  HEAD = 'a' * 40
  BASE = 'main'

  class Client
    attr_accessor :snapshots, :head_checks, :review_result, :mutation_result, :mutation_error, :comments
    attr_reader :mutations, :requested_review, :features
    attr_writer :checks

    def initialize
      @mutations = []
      @features = []
    end

    def snapshot
      value = snapshots.length > 1 ? snapshots.shift : snapshots.first
      raise value if value.is_a?(Exception)

      value
    end

    def required_checks
      raise @checks if @checks.is_a?(Exception)

      @checks
    end

    def checks
      return head_checks || [] unless head_checks&.first.is_a?(Array)

      head_checks.length > 1 ? head_checks.shift : head_checks.first
    end

    def configured_required_checks = []

    def review(id)
      @requested_review = id
      raise review_result if review_result.is_a?(Exception)

      review_result
    end

    def viewer_login = 'shaka-agent'

    def issue_comments = comments

    def compare(_from, _to) = raise(Shaka::Error, 'compare is not stubbed')

    def graphql(query, variables, feature: nil)
      @mutations << [query, variables]
      @features << feature
      raise mutation_error if mutation_error

      mutation_result
    end
  end

  def setup
    @client = Client.new
    @client.snapshots = [snapshot]
    @client.checks = [{ 'name' => 'Validate', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    @client.comments = [attestation_comment]
    @client.review_result = { 'id' => 17, 'commit_id' => HEAD, 'state' => 'COMMENTED', 'body' => 'Walkthrough' }
    @client.mutation_result = { 'mergePullRequest' => { 'pullRequest' => {
      'headRefOid' => HEAD, 'baseRefName' => BASE, 'state' => 'MERGED', 'merged' => true,
      'mergeCommit' => { 'oid' => 'b' * 40 }
    } } }
    @merge = Shaka::Merge.new(@client)
  end

  def attestation_comment
    { 'user' => { 'login' => 'shaka-agent' }, 'html_url' => 'https://example.test/c/1',
      'body' => "Report\n\nREVIEWED #{HEAD} BY openai/codex EFFORT high FINDINGS 0" }
  end

  def snapshot
    { 'id' => 'PR_123', 'headRefOid' => HEAD, 'baseRefName' => BASE, 'state' => 'OPEN', 'isDraft' => false,
      'viewerCanMergeAsAdmin' => false, 'isMergeQueueEnabled' => false, 'isInMergeQueue' => false,
      'mergeQueueEntry' => nil,
      'autoMergeRequest' => nil, 'mergeStateStatus' => 'CLEAN', 'reviewDecision' => nil,
      'changedFiles' => 3, 'additions' => 40, 'deletions' => 10, 'commits' => { 'totalCount' => 2 } }
  end

  def assert_blocked(pattern)
    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }
    assert_match pattern, error.message
    assert_empty @client.mutations
  end

  def queue_entry(head: HEAD, position: nil)
    { 'id' => 'MQE_123', 'position' => position, 'state' => 'AWAITING_CHECKS',
      'headCommit' => { 'oid' => head }, 'baseCommit' => { 'oid' => 'd' * 40 } }.compact
  end

  def assert_queue_result(result, entry)
    assert_equal 'merge_queue', result.fetch('submission')
    assert_equal HEAD, result.fetch('headRefOid')
    assert_equal entry, result.fetch('mergeQueueEntry')
  end
end

class MergeNativeGateTest < Minitest::Test
  include MergeFixtures

  def test_refuses_a_draft_or_closed_pull_request
    [{ 'isDraft' => true }, { 'state' => 'CLOSED' }].each do |changes|
      @client.snapshots = [snapshot.merge(changes)]
      assert_blocked(/open and not a draft/)
    end
  end

  def test_refuses_stale_or_unknown_merge_state
    %w[BEHIND BLOCKED DIRTY DRAFT HAS_HOOKS UNKNOWN].each do |state|
      @client.snapshots = [snapshot.merge('mergeStateStatus' => state)]
      assert_blocked(/not CLEAN or UNSTABLE/)
    end
  end

  # Production break: GitHub reports UNSTABLE when only non-required checks are
  # pending or failing. Requiring CLEAN here holds merge while claude-review or
  # CodeRabbit is still running after validate has passed.
  def test_allows_unstable_when_only_optional_checks_are_pending
    @client.snapshots = [snapshot.merge('mergeStateStatus' => 'UNSTABLE')]

    assert_equal 'MERGED', @merge.call(head: HEAD, base: BASE, walkthrough: 17)['state']
  end

  # Production break: all wait waits for optional review jobs. Allowing
  # UNSTABLE here would merge while claude-review is still pending or red.
  def test_all_wait_refuses_unstable_optional_checks
    merge = Shaka::Merge.new(@client, ci_review_wait: 'all')
    @client.snapshots = [snapshot.merge('mergeStateStatus' => 'UNSTABLE')]

    error = assert_raises(Shaka::Error) { merge.call(head: HEAD, base: BASE, walkthrough: 17) }
    assert_match(/not CLEAN/, error.message)
    assert_empty @client.mutations
  end

  def test_queue_enabled_all_wait_refuses_unstable_enqueue
    merge = Shaka::Merge.new(@client, ci_review_wait: 'all')
    ready = snapshot.merge('isMergeQueueEnabled' => true, 'mergeStateStatus' => 'UNSTABLE')
    @client.snapshots = [ready]

    error = assert_raises(Shaka::Error) { merge.call(head: HEAD, base: BASE, walkthrough: 17) }
    assert_match(/not CLEAN or BEHIND or BLOCKED/, error.message)
    assert_empty @client.mutations
  end

  def test_all_seam_cannot_be_overridden_to_none_at_merge
    merge = Shaka::Merge.new(@client, ci_review_wait: 'none', seam_wait: 'all')
    @client.snapshots = [snapshot.merge('mergeStateStatus' => 'UNSTABLE')]

    error = assert_raises(Shaka::Error) { merge.call(head: HEAD, base: BASE, walkthrough: 17) }
    assert_match(/not CLEAN/, error.message)
    assert_empty @client.mutations
  end

  def test_queue_enabled_pull_request_can_enqueue_when_optional_checks_are_pending
    entry = queue_entry
    ready = snapshot.merge('isMergeQueueEnabled' => true, 'mergeStateStatus' => 'UNSTABLE')
    queued = ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => entry)
    @client.snapshots = [ready, ready, queued]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    assert_equal 'merge_queue', @merge.call(head: HEAD, base: BASE, walkthrough: 17).fetch('submission')
  end

  def test_refuses_bypass_capable_or_unknown_actor
    [true, nil].each do |value|
      @client.snapshots = [snapshot.merge('viewerCanMergeAsAdmin' => value)]
      assert_blocked(/protection must be enforced/)
    end
  end

  def test_refuses_unknown_queue_state
    %w[isMergeQueueEnabled isInMergeQueue].each do |key|
      @client.snapshots = [snapshot.merge(key => nil)]
      assert_blocked(/queue state is unknown/)
    end
  end

  def test_refuses_a_queue_entry_when_github_reports_not_queued
    @client.snapshots = [snapshot.merge('mergeQueueEntry' => { 'id' => 'MQE_123' })]

    assert_blocked(/queue state is inconsistent/)
  end

  def test_refuses_existing_or_unknown_delayed_auto_merge
    @client.snapshots = [snapshot.merge('autoMergeRequest' => { 'enabledAt' => '2026-09-14T00:00:00Z' })]
    assert_blocked(/delayed auto-merge/)
    @client.snapshots = [snapshot.except('autoMergeRequest')]
    assert_blocked(/delayed auto-merge/)
  end

  def test_missing_required_approval_or_changes_requested_blocks
    %w[REVIEW_REQUIRED CHANGES_REQUESTED FUTURE_STATE].each do |state|
      @client.snapshots = [snapshot.merge('reviewDecision' => state)]
      assert_blocked(/Required reviews/)
    end
    @client.snapshots = [snapshot.except('reviewDecision')]
    assert_blocked(/Required reviews/)
  end
end

class MergeReviewEvidenceGateTest < Minitest::Test
  include MergeFixtures

  def test_reports_the_review_evidence_it_merged_on
    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal 'MERGED', result.fetch('state')
    assert_equal 'current_head', result.dig('review_evidence', 'basis')
    assert_equal 'openai/codex', result.dig('review_evidence', 'reviewer')
  end

  def test_refuses_without_review_evidence_before_submitting
    @client.comments = []

    assert_blocked(/No local-review attestation/)
  end

  def test_refuses_evidence_for_another_commit_before_submitting
    @client.comments.first['body'] = "REVIEWED #{'c' * 40} BY openai/codex EFFORT high FINDINGS 0"

    assert_blocked(/earlier attestations do not apply/)
  end

  def test_waiver_merges_and_reports_its_reason
    @client.comments = []
    merge = Shaka::Merge.new(@client, review: { waiver: 'Prose-only change' })

    result = merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal({ 'basis' => 'waived', 'reason' => 'Prose-only change' }, result.fetch('review_evidence'))
  end

  def test_trusted_none_needs_no_review_evidence
    @client.comments = []

    result = Shaka::Merge.new(@client, review: { required: 'none' }).call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal 'not_required', result.dig('review_evidence', 'basis')
  end
end

class MergeCheckTest < Minitest::Test
  include MergeFixtures

  def test_accepts_github_terminal_check_conclusions
    @client.checks = [%w[SUCCESS pass], %w[NEUTRAL skipping], %w[SKIPPED skipping]].map do |state, bucket|
      { 'name' => state, 'state' => state, 'bucket' => bucket }
    end
    assert_equal 'MERGED', @merge.call(head: HEAD, base: BASE, walkthrough: 17)['state']
  end

  def test_empty_or_unknown_check_list_blocks
    [nil, {}].each do |checks|
      @client.checks = checks
      assert_blocked(/No observable required checks/)
    end
  end

  def test_empty_required_checks_name_an_unprotected_repository
    @client.checks = []
    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }
    assert_match(/no required checks/, error.message)
    assert_match(/unprotected/, error.message)
    refute_match(/unavailable|unreadable|unknown/, error.message)
    assert_match(/branch protection/, error.message)
    assert_match(/wait and retry/, error.message)
    assert_empty @client.mutations
  end

  def test_empty_required_checks_point_to_the_seam_fallback
    @client.checks = []
    assert_blocked(/merge\.required_checks/)
  end

  def test_seam_required_checks_gate_merge_when_github_enforces_none
    @client.checks = []
    @client.head_checks = [{ 'name' => 'checks', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    merge = Shaka::Merge.new(@client, seam_required_checks: ['checks'])

    assert_equal 'MERGED', merge.call(head: HEAD, base: BASE, walkthrough: 17)['state']
  end

  def test_a_seam_required_check_missing_from_the_head_blocks
    @client.checks = []
    @client.head_checks = [{ 'name' => 'lint', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    @merge = Shaka::Merge.new(@client, seam_required_checks: ['checks'])

    assert_blocked(/Required check is not passing.*"name" => "checks", "state" => "MISSING"/)
  end

  # GitHub cannot catch a seam check that fails while review evidence is read, so merge rereads it.
  def test_a_seam_required_check_that_fails_during_review_reads_blocks
    @client.checks = []
    @client.head_checks = [[{ 'name' => 'checks', 'state' => 'SUCCESS', 'bucket' => 'pass' }],
                           [{ 'name' => 'checks', 'state' => 'FAILURE', 'bucket' => 'fail' }]]
    @client.snapshots = [snapshot, snapshot.merge('mergeStateStatus' => 'UNSTABLE')]
    @merge = Shaka::Merge.new(@client, seam_required_checks: ['checks'])

    assert_blocked(/Required check is not passing/)
  end

  def test_a_failing_seam_required_check_blocks
    @client.checks = []
    @client.head_checks = [{ 'name' => 'checks', 'state' => 'FAILURE', 'bucket' => 'fail' }]
    @merge = Shaka::Merge.new(@client, seam_required_checks: ['checks'])

    assert_blocked(/Required check is not passing/)
  end

  def test_native_required_checks_are_not_replaced_by_the_seam_list
    @client.checks = [{ 'name' => 'Validate', 'state' => 'FAILURE', 'bucket' => 'fail' }]
    @client.head_checks = [{ 'name' => 'checks', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    @merge = Shaka::Merge.new(@client, seam_required_checks: ['checks'])

    assert_blocked(/Required check is not passing/)
  end

  def test_failed_pending_cancelled_or_unknown_checks_block
    %w[FAILURE ERROR PENDING IN_PROGRESS CANCELLED TIMED_OUT EXPECTED FUTURE_STATE].each do |state|
      @client.checks = [{ 'name' => 'Validate', 'state' => state, 'bucket' => 'pass' }]
      assert_blocked(/Required check/)
    end
  end

  # Production break: UNSTABLE only covers optional checks. A failed required
  # check must still refuse merge even when GitHub reports UNSTABLE.
  def test_unstable_does_not_override_a_failed_required_check
    @client.snapshots = [snapshot.merge('mergeStateStatus' => 'UNSTABLE')]
    @client.checks = [{ 'name' => 'Validate', 'state' => 'FAILURE', 'bucket' => 'fail' }]

    assert_blocked(/Required check/)
  end

  def test_inconsistent_or_malformed_check_results_block
    [nil, 'success', {}, { 'state' => 'SUCCESS', 'bucket' => 'pass' },
     { 'name' => 'Validate', 'state' => 'SUCCESS', 'bucket' => 'pending' },
     { 'name' => 'Validate', 'state' => 'SKIPPED', 'bucket' => 'pass' }].each do |check|
      @client.checks = [check]
      assert_blocked(/Required check/)
    end
  end

  def test_api_failure_does_not_submit
    @client.checks = Shaka::Error.new('GitHub unavailable')
    assert_blocked(/GitHub unavailable/)
  end
end

class MergeWalkthroughTest < Minitest::Test
  include MergeFixtures

  def test_wrong_review_id_or_head_blocks
    [{ 'id' => 99 }, { 'commit_id' => 'c' * 40 }].each do |changes|
      @client.review_result = { 'id' => 17, 'commit_id' => HEAD }.merge(changes)
      assert_blocked(/review on this PR at the expected head/)
    end
  end

  def test_missing_review_on_this_pull_request_blocks
    @client.review_result = Shaka::Error.new('Review not found on this PR')
    assert_blocked(/not found on this PR/)
  end

  def test_pending_approving_or_blank_reviews_do_not_count_as_walkthroughs
    [{ 'state' => 'PENDING' }, { 'state' => 'APPROVED' }, { 'body' => '  ' }, { 'body' => nil }].each do |changes|
      @client.review_result = { 'id' => 17, 'commit_id' => HEAD, 'state' => 'COMMENTED',
                                'body' => 'Tour' }.merge(changes)
      assert_blocked(/submitted COMMENT review/)
    end
  end
end

class MergeQueueSubmissionTest < Minitest::Test
  include MergeFixtures

  def test_enqueues_a_clean_queue_enabled_pull_request_at_the_expected_head
    entry = queue_entry(position: 1)
    ready = snapshot.merge('isMergeQueueEnabled' => true)
    queued = ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => entry)
    @client.snapshots = [ready, ready, queued]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_queue_result(result, entry)
    query, variables = @client.mutations.fetch(0)
    assert_queue_mutation(query, variables)
  end

  def test_queue_enabled_pull_request_can_enqueue_when_the_base_advanced
    entry = queue_entry
    ready = snapshot.merge('isMergeQueueEnabled' => true, 'mergeStateStatus' => 'BEHIND')
    queued = ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => entry)
    @client.snapshots = [ready, ready, queued]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal ['merge_queue', 1], [result.fetch('submission'), @client.mutations.length]
  end

  def test_queue_enabled_pull_request_lets_github_decide_blocked_state
    entry = queue_entry
    ready = snapshot.merge('isMergeQueueEnabled' => true, 'mergeStateStatus' => 'BLOCKED')
    queued = ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => entry)
    @client.snapshots = [ready, ready, queued]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal 'merge_queue', result.fetch('submission')
    assert_equal 1, @client.mutations.length
  end

  def test_queue_enabled_pull_request_rejects_conflicting_or_unknown_state
    %w[DIRTY DRAFT HAS_HOOKS UNKNOWN].each do |state|
      @client.snapshots = [snapshot.merge('isMergeQueueEnabled' => true, 'mergeStateStatus' => state)]
      assert_blocked(/not CLEAN or BEHIND or BLOCKED or UNSTABLE/)
    end
  end

  def test_existing_exact_head_queue_entry_is_idempotent
    entry = queue_entry(position: 2)
    queued = snapshot.merge('isMergeQueueEnabled' => true, 'isInMergeQueue' => true,
                            'mergeQueueEntry' => entry, 'mergeStateStatus' => 'UNKNOWN')
    @client.snapshots = [queued]

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal 'merge_queue', result.fetch('submission')
    assert_equal entry, result.fetch('mergeQueueEntry')
    assert_empty @client.mutations
  end

  def test_queue_submission_requires_a_confirmed_entry
    @client.snapshots = [snapshot.merge('isMergeQueueEnabled' => true)]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => nil } }

    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }

    assert_match(/did not confirm enqueueing.*inspect live PR state/, error.message)
  end

  def test_enqueue_accepts_a_nullable_mutation_head_when_readback_proves_the_target
    returned = queue_entry.merge('headCommit' => nil)
    confirmed = queue_entry
    ready = snapshot.merge('isMergeQueueEnabled' => true)
    queued = ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => confirmed)
    @client.snapshots = [ready, ready, queued]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => returned } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_queue_result(result, confirmed)
  end

  def test_existing_queue_entry_for_another_head_is_not_replayed
    queued = snapshot.merge('isMergeQueueEnabled' => true, 'isInMergeQueue' => true,
                            'mergeQueueEntry' => queue_entry(head: 'c' * 40), 'mergeStateStatus' => 'UNKNOWN')
    @client.snapshots = [queued]

    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }

    assert_match(/without the expected head entry/, error.message)
    assert_empty @client.mutations
  end

  def test_changed_base_after_reading_checks_blocks_before_submission
    @client.snapshots = [snapshot, snapshot.merge('baseRefName' => 'release')]

    assert_blocked(/base changed/)
  end

  def test_queue_submission_rejects_post_enqueue_retargeting
    entry = queue_entry
    ready = snapshot.merge('isMergeQueueEnabled' => true)
    retargeted = ready.merge('baseRefName' => 'release', 'isInMergeQueue' => true, 'mergeQueueEntry' => entry)
    @client.snapshots = [ready, ready, retargeted]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }

    assert_match(/did not confirm queueing the expected head and base.*inspect live PR state/, error.message)
    assert_equal 1, @client.mutations.length
  end

  private

  def assert_queue_mutation(query, variables)
    assert_includes query, 'enqueuePullRequest'
    assert_includes query, 'expectedHeadOid: $head'
    assert_equal({ 'id' => 'PR_123', 'head' => HEAD }, variables)
    assert_equal ['merge_queue'], @client.features
  end
end

class MergeQueueReconciliationTest < Minitest::Test
  include MergeFixtures

  def test_replay_does_not_reenqueue_an_entry_removed_while_reading_gates
    entry = queue_entry
    queued = snapshot.merge('isMergeQueueEnabled' => true, 'isInMergeQueue' => true,
                            'mergeQueueEntry' => entry, 'mergeStateStatus' => 'UNKNOWN')
    removed = snapshot.merge('isMergeQueueEnabled' => true, 'mergeStateStatus' => 'BLOCKED')
    @client.snapshots = [queued, removed]

    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }

    assert_match(/left the merge queue.*meaningful change/, error.message)
    assert_empty @client.mutations
  end

  def test_replay_reconciles_a_merge_that_finishes_while_reading_gates
    entry = queue_entry
    queued = snapshot.merge('isMergeQueueEnabled' => true, 'isInMergeQueue' => true,
                            'mergeQueueEntry' => entry, 'mergeStateStatus' => 'UNKNOWN')
    merged = queued.merge('state' => 'MERGED', 'merged' => true, 'mergeCommit' => { 'oid' => 'e' * 40 },
                          'isInMergeQueue' => false, 'mergeQueueEntry' => nil)
    @client.snapshots = [queued, merged]

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_equal 'MERGED', result.fetch('state')
    assert_equal 'e' * 40, result.dig('mergeCommit', 'oid')
    assert_empty @client.mutations
  end

  def test_enqueue_that_merges_before_readback_returns_terminal_evidence
    entry = queue_entry
    ready = snapshot.merge('isMergeQueueEnabled' => true)
    merged = ready.merge('state' => 'MERGED', 'merged' => true, 'mergeCommit' => { 'oid' => 'e' * 40 })
    @client.snapshots = [ready, ready, merged]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => entry } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_queue_result(result, entry)
    assert_equal 'MERGED', result.fetch('state')
    assert_equal 'e' * 40, result.dig('mergeCommit', 'oid')
  end

  def test_enqueue_reconciles_a_replacement_entry_for_the_same_target
    returned = queue_entry
    replacement = queue_entry.merge('id' => 'MQE_456')
    ready = snapshot.merge('isMergeQueueEnabled' => true)
    queued = ready.merge('isInMergeQueue' => true, 'mergeQueueEntry' => replacement)
    @client.snapshots = [ready, ready, queued]
    @client.mutation_result = { 'enqueuePullRequest' => { 'mergeQueueEntry' => returned } }

    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_queue_result(result, replacement)
  end
end

class MergeSubmissionTest < Minitest::Test
  include MergeFixtures

  def test_rejects_invalid_head_before_submission
    [nil, '', 'main'].each do |head|
      error = assert_raises(Shaka::Error) { @merge.call(head: head, base: BASE, walkthrough: 17) }
      assert_match(/full commit SHA/, error.message)
    end
    assert_empty @client.mutations
  end

  def test_a_pr_that_never_targeted_the_validated_base_blocks
    @client.snapshots = [snapshot.merge('baseRefName' => 'release-2.x')]
    assert_blocked(/targets "release-2\.x", not the validated base "main"/)
  end

  def test_a_retarget_while_reading_gates_blocks
    @client.snapshots = [snapshot, snapshot.merge('baseRefName' => 'release-2.x')]
    assert_blocked(/PR base changed/)
  end

  def test_rejects_a_missing_base_before_submission
    [nil, '', '  '].each do |base|
      error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: base, walkthrough: 17) }
      assert_match(/validated against/, error.message)
    end
    assert_empty @client.mutations
  end

  def test_initial_stale_head_or_missing_identity_blocks
    @client.snapshots = [snapshot.merge('headRefOid' => 'c' * 40)]
    assert_blocked(/PR head changed/)
    @client.snapshots = [snapshot.except('id')]
    assert_blocked(/identity is missing/)
    @client.snapshots = [snapshot.except('baseRefName')]
    assert_blocked(/base is missing/)
  end

  def test_passes_expected_head_to_server_and_returns_native_merge_result
    @client.snapshots = [snapshot.merge('reviewDecision' => 'APPROVED')]
    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)
    assert_equal 'b' * 40, result.dig('mergeCommit', 'oid')
    assert_equal 17, @client.requested_review
    query, variables = @client.mutations.fetch(0)
    assert_includes query, 'expectedHeadOid: $head'
    assert_equal({ 'id' => 'PR_123', 'head' => HEAD }, variables)
    assert_equal 1, @client.mutations.length
  end

  # The mutation cannot pin a base, so the branch it merged into is the only evidence a
  # retarget inside that last request leaves behind.
  def test_reports_the_base_the_merge_landed_on
    @client.snapshots = [snapshot.merge('reviewDecision' => 'APPROVED')]
    result = @merge.call(head: HEAD, base: BASE, walkthrough: 17)

    assert_includes @client.mutations.fetch(0).first, 'baseRefName'
    assert_equal BASE, result.fetch('baseRefName')
  end

  def test_changed_head_after_reading_checks_blocks
    @client.snapshots = [snapshot, snapshot.merge('headRefOid' => 'c' * 40)]
    assert_blocked(/PR head changed/)
  end

  def test_changed_gate_after_reading_checks_blocks
    @client.snapshots = [snapshot, snapshot.merge('reviewDecision' => 'CHANGES_REQUESTED')]
    assert_blocked(/Required reviews/)
  end

  def test_head_change_at_server_is_rejected_without_retry
    @client.mutation_error = Shaka::Error.new('Head branch was modified')
    error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }
    assert_match(/Head branch was modified.*inspect live PR state/, error.message)
    assert_equal 1, @client.mutations.length
  end

  def test_unknown_mutation_outcome_requires_inspection
    [nil, 'merged', { 'pullRequest' => { 'state' => 'MERGED' } }].each do |payload|
      @client.mutation_result = { 'mergePullRequest' => payload }
      error = assert_raises(Shaka::Error) { @merge.call(head: HEAD, base: BASE, walkthrough: 17) }
      assert_match(/did not confirm.*inspect live PR state/, error.message)
    end
    assert_equal 3, @client.mutations.length
  end

  def test_snapshot_failure_does_not_submit
    @client.snapshots = [Shaka::Error.new('Snapshot unavailable')]
    assert_blocked(/Snapshot unavailable/)
  end
end

class MergeLimitsGateTest < Minitest::Test
  include MergeFixtures

  LIMITS = { 'max_changed_files' => 3, 'max_changed_lines' => 50, 'max_commits' => 2 }.freeze

  def merge_with(confirmed_head: nil)
    @merge.call(head: HEAD, base: BASE, walkthrough: 17,
                limits: Shaka::MergeLimits.new(LIMITS, confirmed_head:))
  end

  def assert_limit_blocked(pattern, confirmed_head: nil)
    error = assert_raises(Shaka::Error) { merge_with(confirmed_head:) }
    assert_match pattern, error.message
    assert_empty @client.mutations
  end

  def test_counts_at_each_limit_merge
    assert_equal 'MERGED', merge_with.fetch('state')
  end

  def test_one_past_any_limit_hands_back_as_ask
    [{ 'changedFiles' => 4 }, { 'deletions' => 11 }, { 'commits' => { 'totalCount' => 3 } }].each do |change|
      @client.snapshots = [snapshot.merge(change)]
      assert_limit_blocked(/exceeds merge limits .*hand it to the user as Ask/)
    end
  end

  def test_missing_size_evidence_hands_back_as_ask
    [{ 'changedFiles' => nil }, { 'additions' => '40' }, { 'commits' => nil }, { 'commits' => {} },
     { 'changedFiles' => -1 }].each do |change|
      @client.snapshots = [snapshot.merge(change)]
      assert_limit_blocked(/did not report the PR size/)
    end
  end

  def test_confirmation_for_the_current_head_merges_past_limits
    @client.snapshots = [snapshot.merge('changedFiles' => 400, 'commits' => nil)]
    assert_equal 'MERGED', merge_with(confirmed_head: HEAD).fetch('state')
  end

  def test_confirmation_for_another_head_needs_a_new_decision
    assert_limit_blocked(/names c{40}, not the current head/, confirmed_head: 'c' * 40)
  end

  def test_confirmation_does_not_relax_native_gates
    @client.snapshots = [snapshot.merge('changedFiles' => 400, 'mergeStateStatus' => 'BLOCKED')]
    assert_limit_blocked(/GitHub merge state/, confirmed_head: HEAD)
  end

  def test_a_count_that_grows_before_submission_hands_back_as_ask
    @client.snapshots = [snapshot, snapshot.merge('changedFiles' => 4)]
    assert_limit_blocked(/files 4 > 3/)
  end

  def test_default_limits_apply_when_the_caller_passes_none
    @client.snapshots = [snapshot.merge('changedFiles' => 30)]
    assert_blocked(/files 30 > 29/)
  end
end
