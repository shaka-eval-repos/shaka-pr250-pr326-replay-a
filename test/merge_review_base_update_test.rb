# frozen_string_literal: true

require_relative 'merge_review_evidence_test'

# Bringing a reviewed branch up to date with its base keeps the review when the head is exactly a
# clean merge of the reviewed commit with the new base. MergeTreeProofTest covers the Git proof.
class MergeReviewBaseUpdateTest < Minitest::Test
  include MergeReviewEvidenceFixtures

  NEW_BASE = 'f' * 40

  # Records what it was asked and answers with a fixed verdict.
  class Proof
    attr_reader :asked

    def initialize(problem) = @problem = problem

    def problem(**commits)
      @asked = commits
      @problem
    end
  end

  def setup
    super
    @client.comments = [attestation(EARLIER)]
    @client.comparisons = { EARLIER => { 'status' => 'diverged', 'files' => [] },
                            ['main', HEAD] => { 'merge_base_commit' => { 'sha' => NEW_BASE } } }
  end

  def comparison(problem)
    @proof = Proof.new(problem)
    Shaka::MergeReviewComparison.new(@client, head: HEAD, base: 'main', proof: @proof)
  end

  def test_a_proven_clean_update_keeps_the_review
    rejected = []

    assert_equal({ 'basis' => 'unchanged_since_review' }, comparison(nil).match(EARLIER, rejected))
    assert_equal({ reviewed: EARLIER, base: NEW_BASE, head: HEAD }, @proof.asked)
  end

  def test_a_failed_proof_records_why
    rejected = []

    assert_nil comparison('the head differs from a clean merge').match(EARLIER, rejected)
    assert_includes rejected.last, 'the head differs from a clean merge'
  end

  def test_an_unreadable_base_comparison_is_recorded
    @client.comparisons.delete(['main', HEAD])
    @client.comparisons['main'] = Shaka::Error.new('gh api compare failed.')
    rejected = []

    assert_nil comparison(nil).match(EARLIER, rejected)
    assert_match(/base comparison unavailable/, rejected.last)
  end

  def test_evidence_uses_the_checkout_for_the_proof
    Dir.mktmpdir do |outside|
      error = assert_raises(Shaka::Error) do
        Shaka::MergeReviewEvidence.new(@client, required: 'meaningful_changes', root: outside).call(HEAD, base: 'main')
      end

      assert_match(/not available locally/, error.message)
    end
  end

  def test_without_a_checkout_only_the_markdown_rule_applies
    evidence = Shaka::MergeReviewEvidence.new(@client, required: 'meaningful_changes')

    assert_raises(Shaka::Error) { evidence.call(HEAD, base: 'main') }
    refute_includes @client.compared, ['main', HEAD]
  end
end
