# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/merge_review_evidence'

module MergeReviewEvidenceFixtures
  HEAD = 'a' * 40
  EARLIER = 'c' * 40
  ACCOUNT = 'shaka-agent'

  # Serves the three GitHub reads evidence needs.
  class Client
    attr_accessor :comments, :comparisons
    attr_reader :compared

    def initialize
      @comments = []
      @comparisons = {}
      @compared = []
    end

    def viewer_login = ACCOUNT

    def issue_comments = comments

    def compare(from, to)
      @compared << [from, to]
      result = comparisons.fetch([from, to]) { comparisons.fetch(from) { raise Shaka::Error, 'gh api compare failed.' } }
      raise result if result.is_a?(Exception)

      result
    end
  end

  def setup
    @client = Client.new
  end

  def attestation(sha, reviewer: 'openai/codex', author: ACCOUNT, url: 'https://example.test/c/1')
    { 'user' => { 'login' => author }, 'html_url' => url,
      'body' => "<!-- shaka:reply:review -->\nNo findings.\n\nREVIEWED #{sha} BY #{reviewer} EFFORT high FINDINGS 0\n" }
  end

  def evidence(required: 'meaningful_changes', waiver: nil)
    Shaka::MergeReviewEvidence.new(@client, required:, waiver:).call(HEAD)
  end

  def markdown_only(*names)
    { 'status' => 'ahead', 'files' => names.map { |name| { 'filename' => name, 'status' => 'modified' } } }
  end
end

class MergeReviewEvidenceTest < Minitest::Test
  include MergeReviewEvidenceFixtures

  def test_accepts_an_attestation_for_the_exact_head
    @client.comments = [attestation(HEAD)]

    result = evidence

    assert_equal 'current_head', result.fetch('basis')
    assert_equal HEAD, result.fetch('reviewed')
    assert_equal 'openai/codex', result.fetch('reviewer')
    assert_equal 'https://example.test/c/1', result.fetch('comment')
    assert_empty @client.compared
  end

  def test_accepts_a_same_model_review
    @client.comments = [attestation(HEAD, reviewer: 'anthropic/claude')]

    assert_equal 'anthropic/claude', evidence.fetch('reviewer')
  end

  # Review identities keep their configured case and may contain spaces, as `review check` accepts.
  def test_accepts_any_identity_the_review_checker_accepts
    ['OpenAI/Codex', 'acme/my model'].each do |reviewer|
      @client.comments = [attestation(HEAD, reviewer:)]

      assert_equal reviewer, evidence.fetch('reviewer')
    end
  end

  def test_ignores_an_identity_the_review_checker_rejects
    @client.comments = [attestation(HEAD, reviewer: 'openai/codex/extra')]

    assert_raises(Shaka::Error) { evidence }
  end

  # The attestation closes a report; a quoted or retracted line is not evidence.
  def test_ignores_an_attestation_that_does_not_close_the_comment
    line = "REVIEWED #{HEAD} BY openai/codex EFFORT high FINDINGS 0"
    ["```\n#{line}\n```", "#{line}\n\nRetracted: this review was for another branch."].each do |body|
      @client.comments = [{ 'user' => { 'login' => ACCOUNT }, 'body' => body }]

      assert_raises(Shaka::Error) { evidence }
    end
  end

  def test_refuses_when_no_attestation_exists
    error = assert_raises(Shaka::Error) { evidence }

    assert_match(/No local-review attestation/, error.message)
    assert_match(/--review-waiver/, error.message)
  end

  def test_ignores_attestations_other_accounts_wrote
    @client.comments = [attestation(HEAD, author: 'someone-else')]

    assert_raises(Shaka::Error) { evidence }
  end

  def test_ignores_an_attestation_that_is_not_its_own_line
    @client.comments = [{ 'user' => { 'login' => ACCOUNT },
                          'body' => "Quoted: `REVIEWED #{HEAD} BY openai/codex EFFORT high FINDINGS 0`" }]

    assert_raises(Shaka::Error) { evidence }
  end

  def test_accepts_an_earlier_attestation_when_only_markdown_changed_since
    @client.comments = [attestation(EARLIER)]
    @client.comparisons = { EARLIER => markdown_only('README.md', 'docs/Guide.MD') }

    result = evidence

    assert_equal 'markdown_only_since_review', result.fetch('basis')
    assert_equal EARLIER, result.fetch('reviewed')
    assert_equal %w[README.md docs/Guide.MD], result.fetch('changed_since_review')
    assert_equal [[EARLIER, HEAD]], @client.compared
  end

  def test_refuses_an_earlier_attestation_when_code_changed_since
    @client.comments = [attestation(EARLIER)]
    @client.comparisons = { EARLIER => markdown_only('README.md', 'lib/merge.rb') }

    error = assert_raises(Shaka::Error) { evidence }

    assert_includes error.message, EARLIER
    assert_match(%r{need fresh review: lib/merge\.rb}, error.message)
  end

  def test_refuses_an_earlier_attestation_when_agent_instructions_changed_since
    paths = %w[AGENTS.md skills/shaka/references/review.md .agents/writing-style.md
               pkg/.github/pull_request_template.md]
    paths.each do |path|
      @client.comments = [attestation(EARLIER)]
      @client.comparisons = { EARLIER => markdown_only('README.md', path) }

      error = assert_raises(Shaka::Error) { evidence }
      assert_includes error.message, path
    end
  end

  def test_refuses_a_rename_from_a_non_markdown_path
    @client.comments = [attestation(EARLIER)]
    @client.comparisons = { EARLIER => { 'status' => 'ahead', 'files' => [
      { 'filename' => 'notes.md', 'previous_filename' => 'run.rb', 'status' => 'renamed' }
    ] } }

    assert_raises(Shaka::Error) { evidence }
  end

  # After a rebase the reviewed commit is no longer an ancestor, so its diff says nothing about the head.
  def test_refuses_an_attestation_that_is_not_an_ancestor
    @client.comments = [attestation(EARLIER)]
    @client.comparisons = { EARLIER => markdown_only('README.md').merge('status' => 'diverged') }

    assert_raises(Shaka::Error) { evidence }
  end

  def test_refuses_a_comparison_that_may_be_truncated
    @client.comments = [attestation(EARLIER)]
    names = Array.new(Shaka::MergeReviewComparison::COMPARE_FILE_LIMIT) { |index| "docs/#{index}.md" }
    @client.comparisons = { EARLIER => markdown_only(*names) }

    assert_raises(Shaka::Error) { evidence }
  end

  def test_an_unreadable_comparison_does_not_hide_a_usable_older_attestation
    older = 'd' * 40
    @client.comments = [attestation(older), attestation(EARLIER)]
    @client.comparisons = { older => markdown_only('README.md') }

    assert_equal older, evidence.fetch('reviewed')
  end
end

class MergeReviewWaiverTest < Minitest::Test
  include MergeReviewEvidenceFixtures

  def test_waiver_is_reported_when_no_evidence_exists
    result = evidence(waiver: '  Prose-only change; claude-review covered it  ')

    assert_equal 'waived', result.fetch('basis')
    assert_equal 'Prose-only change; claude-review covered it', result.fetch('reason')
  end

  def test_waiver_survives_an_unreadable_comment_list
    def @client.issue_comments = raise(Shaka::Error, 'Comment listing exceeds 20 pages.')

    result = evidence(waiver: 'CI review covered this head')

    assert_equal 'waived', result.fetch('basis')
    assert_equal 'Comment listing exceeds 20 pages.', result.fetch('evidence_unavailable')
  end

  def test_unreadable_comment_list_without_a_waiver_still_refuses
    def @client.issue_comments = raise(Shaka::Error, 'Comment listing exceeds 20 pages.')

    assert_raises(Shaka::Error) { evidence }
  end

  def test_evidence_is_preferred_over_a_waiver
    @client.comments = [attestation(HEAD)]

    assert_equal 'current_head', evidence(waiver: 'not needed').fetch('basis')
  end

  def test_blank_waiver_is_refused
    error = assert_raises(Shaka::Error) { evidence(waiver: '  ') }

    assert_match(/--review-waiver needs a reason/, error.message)
  end

  def test_review_required_none_needs_no_evidence
    assert_equal 'not_required', evidence(required: 'none').fetch('basis')
  end
end
