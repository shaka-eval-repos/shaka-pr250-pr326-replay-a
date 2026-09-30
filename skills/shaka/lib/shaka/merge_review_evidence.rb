# frozen_string_literal: true

require_relative 'error'
require_relative 'reviewer_selection'
require_relative 'merge_review_comparison'
require_relative 'merge_tree_proof'

module Shaka
  # Finds the published local-review attestation an agent-driven merge relies on.
  #
  # A comment proves that this merging account published an attestation line for a commit. It
  # does not prove a reviewer process ran, which model answered, or that findings were fixed;
  # the result reports what the line claims so the record does not overstate it.
  class MergeReviewEvidence
    # Like LocalReviewEvidence, the line must close the report; ReviewerSelection judges the identity.
    ATTESTATION = /(?:\A|\n)REVIEWED ([0-9a-f]{40}) BY ([^\n]+?) EFFORT (\S+) FINDINGS (\d+)\s*\z/
    # Bounds compare requests when many earlier revisions were reviewed.
    EARLIER_CANDIDATES = 5

    def initialize(github, required: nil, waiver: nil, root: nil)
      @github = github
      @required = required
      @waiver = waiver
      @proof = root && MergeTreeProof.new(root)
    end

    # With the PR's base branch and a checkout `root`, a review also survives a clean update from that base.
    def call(head, base: nil)
      return { 'basis' => 'not_required' } if @required == 'none'

      reason = waiver_reason
      found = attestations(reason)
      return found if found.is_a?(Hash)

      rejected = []
      comparison = MergeReviewComparison.new(@github, head:, base:, proof: @proof)
      evidence = published_evidence(found, head, comparison, rejected)
      return evidence if evidence
      return { 'basis' => 'waived', 'reason' => reason } if reason

      raise Error, refusal(head, rejected)
    end

    private

    def waiver_reason
      return if @waiver.nil?

      reason = @waiver.to_s.strip
      raise Error, '--review-waiver needs a reason' if reason.empty?

      reason
    end

    # A waiver must still work when GitHub cannot list the comments that would make it unnecessary.
    def attestations(reason)
      published_attestations
    rescue Error => e
      raise unless reason

      { 'basis' => 'waived', 'reason' => reason, 'evidence_unavailable' => e.message }
    end

    # Newest first, so the latest review of a revision is the one reported.
    def published_attestations
      account = @github.viewer_login
      @github.issue_comments.reverse.filter_map do |comment|
        next unless comment.is_a?(Hash) && comment.dig('user', 'login') == account

        attestation(comment)
      end
    end

    def attestation(comment)
      sha, reviewer, effort, findings = comment['body'].to_s.match(ATTESTATION)&.captures
      return unless sha && reviewer_identity?(reviewer)

      { 'reviewed' => sha, 'reviewer' => reviewer, 'effort' => effort,
        'findings' => findings.to_i, 'comment' => comment['html_url'] }.compact
    end

    def reviewer_identity?(text)
      ReviewerSelection.parse(text)
      true
    rescue Error
      false
    end

    def published_evidence(found, head, comparison, rejected)
      current = found.find { |entry| entry['reviewed'] == head }
      return current.merge('basis' => 'current_head') if current

      found.uniq { |entry| entry['reviewed'] }.first(EARLIER_CANDIDATES).each do |entry|
        match = comparison.match(entry['reviewed'], rejected)
        return entry.merge(match) if match
      end
      nil
    end

    def refusal(head, rejected)
      detail = if rejected.empty?
                 "No local-review attestation for #{head} was published on this PR by the merging account."
               else
                 "No local-review attestation covers #{head}; earlier attestations do not apply: " \
                   "#{rejected.join('; ')}."
               end
      "#{detail} Publish the review report with its closing `REVIEWED <head> BY <provider>/<family> " \
        'EFFORT <effort> FINDINGS <n>` line, or pass --review-waiver REASON when review was ' \
        'intentionally skipped or a CI review covered this head.'
    end
  end
end
