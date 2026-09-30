# frozen_string_literal: true

require_relative 'error'
require_relative 'merge_target'
require_relative 'merge_submission'
require_relative 'ci_review_wait'
require_relative 'required_checks'
require_relative 'merge_review_evidence'
require_relative 'merge_required_checks'
require_relative 'merge_limits'

module Shaka
  # Applies native GitHub gates; the calling skill must establish merge authority.
  class Merge
    include MergeRequiredChecks

    # `review` takes MergeReviewEvidence's `required`, `waiver`, and checkout `root`.
    def initialize(github, ci_review_wait: nil, seam_wait: nil, review: {}, seam_required_checks: nil)
      @github = github
      @seam_required_checks = seam_required_checks
      @ci_review_wait = CiReviewWait.effective(seam: seam_wait, override: ci_review_wait)
      @review_evidence = MergeReviewEvidence.new(github, **review)
      @submission = MergeSubmission.new(github)
    end

    # `squash_message` is a SquashMessage, or nil for the repository's squash default.
    def call(head:, base:, walkthrough:, limits: MergeLimits.new, squash_message: nil)
      @target = MergeTarget.required!(head, base, limits)
      @submission.message = squash_message
      initial = @github.snapshot
      verify_snapshot(initial, head, @target)
      evidence = verify_reviews(head, base, walkthrough, verify_gate)
      current = @github.snapshot
      return reconcile_queued_replay(initial, current, head).merge(evidence) if initial['isInMergeQueue']

      verify_snapshot(current, head)
      @target.unchanged!(initial, current)
      @submission.call(current, head).merge(evidence)
    end

    private

    def verify_gate
      gate = RequiredChecks.new(@github, seam_names: @seam_required_checks).call
      verify_checks(gate.fetch('checks'))
      gate
    end

    # The walkthrough explains the change; the attestation records that a separate review ran.
    # GitHub cannot catch a seam check that fails while these are read, so it is read again.
    def verify_reviews(head, base, walkthrough, gate)
      verify_walkthrough(@github.review(walkthrough), head, walkthrough)
      evidence = { 'review_evidence' => @review_evidence.call(head, base:) }
      verify_gate if gate['source'] == 'seam'
      evidence
    end

    def reconcile_queued_replay(initial, current, head)
      unless current['state'] == 'MERGED'
        verify_snapshot(current, head)
        @target.unchanged!(initial, current)
      end

      @submission.reconcile_queued(initial, current, head)
    end

    def verify_snapshot(pull, head, target = nil)
      verify_identity(pull, head)
      target&.validated!(pull)
      verify_submission_mode(pull)
      verify_native_state(pull)
    end

    def verify_identity(pull, head)
      raise Error, 'PR head changed; refresh verification and walkthrough' unless pull['headRefOid'] == head
      raise Error, 'PR must be open and not a draft' unless pull['state'] == 'OPEN' && pull['isDraft'] == false

      verify_pull_fields(pull)
    end

    def verify_pull_fields(pull)
      raise Error, 'GitHub PR identity is missing' unless pull['id'].is_a?(String) && !pull['id'].empty?
      raise Error, 'GitHub PR base is missing' unless pull['baseRefName'].is_a?(String) && !pull['baseRefName'].empty?
    end

    def verify_submission_mode(pull)
      raise Error, 'Native protection must be enforced for this actor' unless pull['viewerCanMergeAsAdmin'] == false

      queue_enabled = pull['isMergeQueueEnabled']
      in_queue = pull['isInMergeQueue']
      verify_queue_state(pull, queue_enabled, in_queue)
      return if in_queue
      return if pull.key?('autoMergeRequest') && pull['autoMergeRequest'].nil?

      raise Error, 'Existing or unknown delayed auto-merge blocks immediate merge'
    end

    def verify_queue_state(pull, queue_enabled, in_queue)
      booleans = [true, false]
      raise Error, 'Merge queue state is unknown' unless booleans.include?(queue_enabled) && booleans.include?(in_queue)
      raise Error, 'Merge queue state is inconsistent' if in_queue && !queue_enabled

      verify_queue_entry_absence(pull) unless in_queue
    end

    def verify_queue_entry_absence(pull)
      return if pull.key?('mergeQueueEntry') && pull['mergeQueueEntry'].nil?

      raise Error, 'Merge queue state is inconsistent'
    end

    def verify_native_state(pull)
      unless pull['isInMergeQueue']
        verify_merge_state(pull, CiReviewWait.allowed_merge_states(@ci_review_wait, pull['isMergeQueueEnabled']))
      end

      verify_review_state(pull)
    end

    def verify_merge_state(pull, allowed)
      return if allowed.include?(pull['mergeStateStatus'])

      raise Error, "GitHub merge state is not #{allowed.join(' or ')}: #{pull['mergeStateStatus'].inspect}"
    end

    def verify_review_state(pull)
      return if pull.key?('reviewDecision') && [nil, 'APPROVED'].include?(pull['reviewDecision'])

      raise Error, 'Required reviews are not satisfied or their state is unknown'
    end

    def verify_walkthrough(review, head, id)
      unless review.is_a?(Hash) && review['id'].to_s == id.to_s && review['commit_id'] == head
        raise Error, 'Walkthrough must identify a review on this PR at the expected head'
      end
      return if review['state'] == 'COMMENTED' && review['body'].is_a?(String) && !review['body'].strip.empty?

      raise Error, 'Walkthrough must be a submitted COMMENT review with a nonempty body'
    end
  end
end
