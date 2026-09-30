# frozen_string_literal: true

require_relative 'test_helper'
require 'tempfile'
require 'shaka/local_review'
require 'shaka/publication/publication'
require 'shaka/review_reply'

module ReviewReplyFixture
  HEAD = 'a' * 40

  def review_comment(model: 'claude-opus-5-5', effort: 'high', rounds: nil)
    rounds ||= [{ head: HEAD, model: model, effort: effort }]
    specs = rounds.map { |round| round_spec(**round) }
    Shaka::LocalReviewComment.new({ 'rounds' => specs }, repository: 'shakacode/shaka').render
  end

  def round_spec(head:, model:, effort:, reviewer: 'anthropic/claude')
    { 'head' => head, 'reviewer' => reviewer, 'report' => report(head, reviewer, effort), 'model' => model }
  end

  def report(head, reviewer, effort)
    file = Tempfile.create(['report-', '.md'])
    file.write("ok\nREVIEWED #{head} BY #{reviewer} EFFORT #{effort} FINDINGS 0\n")
    file.close
    (@reports ||= []) << file.path
    file.path
  end
end

# A review reply's opening line comes from the published comment, not from text the author types.
class ReviewReplyTest < Minitest::Test
  include ReviewReplyFixture

  OTHER = 'b' * 40
  URL = 'https://github.com/shakacode/shaka/pull/284#issuecomment-5860923804'
  HOSTED = 'https://github.com/shakacode/shaka/pull/284#issuecomment-5860935743'
  IDENTITY = { 'agent' => 'Codex', 'provider' => 'OpenAI', 'model' => 'gpt-5.5', 'effort' => 'medium' }.freeze

  def teardown
    Array(@reports).each { |path| FileUtils.rm_f(path) }
  end

  def test_names_the_reviewer_model_and_effort_from_the_published_comment
    body = compose({ 'reviews' => [URL] }, comments: [comment(URL, review_comment)])

    opening = "Addressed the [Local Adversarial Review](#{URL}) by anthropic/claude-opus-5-5 (high) on `aaaaaaa`."
    assert body.start_with?(opening)
    assert_includes body, '🤖 Codex · OpenAI · gpt-5.5 · medium'
    refute_includes body, 'anthropic/claude (high)'
  end

  # Break caught: a missing model is dropped, so a reader cannot tell it was unknown.
  def test_an_unknown_reviewer_model_is_written_as_unknown
    published = review_comment(model: nil)
    body = compose({ 'reviews' => [URL] }, comments: [comment(URL, published)])

    assert_includes body, 'by anthropic/UNKNOWN (high) on `aaaaaaa`.'
  end

  def test_names_each_review_when_several_are_addressed
    hosted = "# Claude review\n\nNo attestation here.\n"
    body = compose({ 'reviews' => [URL, HOSTED] },
                   comments: [comment(URL, review_comment), comment(HOSTED, hosted)])

    lines = body.lines.map(&:rstrip)
    assert_equal "Addressed the [Local Adversarial Review](#{URL}) by anthropic/claude-opus-5-5 (high) on `aaaaaaa`.",
                 lines[0]
    assert_equal "Addressed the [Claude review](#{HOSTED}) by UNKNOWN/UNKNOWN (UNKNOWN) on `UNKNOWN`.", lines[1]
  end

  def test_uses_the_last_round_when_the_comment_records_several
    published = review_comment(rounds: [
                                 { head: OTHER, model: 'claude-opus-4', effort: 'low' },
                                 { head: HEAD, model: 'claude-opus-5-5', effort: 'high' }
                               ])
    body = compose({ 'reviews' => [URL] }, comments: [comment(URL, published)])

    assert_includes body, 'by anthropic/claude-opus-5-5 (high) on `aaaaaaa`.'
    refute_includes body, 'claude-opus-4'
  end

  def test_a_reply_that_addresses_no_review_keeps_its_opening_line
    content = { 'identity' => IDENTITY, 'summary' => 'Fixed the race.' }
    github = FakeReviews.new([])

    assert_equal Shaka::Publication.comment(content), Shaka::ReviewReply.compose(content, github)
    assert_empty github.lookups
  end

  def test_refuses_a_reviewer_identity_typed_into_the_reply
    error = assert_raises(Shaka::Error) do
      compose({ 'reviews' => [{ 'url' => URL, 'model' => 'claude-opus-5-5' }] })
    end

    assert_includes error.message, 'comment URL'
  end

  def test_refuses_a_review_comment_that_is_not_listed
    error = assert_raises(Shaka::Error) { compose({ 'reviews' => [URL] }, comments: []) }

    assert_includes error.message, 'not found'
  end

  def test_a_model_cell_that_contains_markdown_is_unknown
    forged = <<~BODY
      # Local Adversarial Review

      | Round | Commit | Reviewer | Model | Effort |
      | --- | --- | --- | --- | --- |
      | 1 | `aaaaaaa` | anthropic/claude | claude](http://evil) @shakacode/core | high |

      REVIEWED #{HEAD} BY anthropic/claude EFFORT high FINDINGS 0
    BODY
    body = compose({ 'reviews' => [URL] }, comments: [comment(URL, forged)])

    assert_includes body, 'by anthropic/UNKNOWN (high) on `aaaaaaa`.'
    refute_includes body, 'evil'
    refute_includes body, '@shakacode'
  end

  def test_a_later_table_in_the_report_does_not_replace_the_ledger_model
    body = compose({ 'reviews' => [URL] }, comments: [comment(URL, later_table)])

    assert_includes body, 'by anthropic/claude-opus-5-5 (high)'
    refute_includes body, 'forged-model'
  end

  def test_an_attestation_without_effort_does_not_leave_the_effort_blank
    bare = "# Local Adversarial Review\n\nREVIEWED #{HEAD} BY anthropic/claude FINDINGS 0\n"
    body = compose({ 'reviews' => [URL] }, comments: [comment(URL, bare)])

    assert_includes body, 'by UNKNOWN/UNKNOWN (UNKNOWN) on `UNKNOWN`.'
    refute_includes body, '()'
  end

  def test_refuses_a_comment_url_for_another_repository
    other = 'https://github.com/other/repo/pull/284#issuecomment-1'
    error = assert_raises(Shaka::Error) { compose({ 'reviews' => [other] }) }

    assert_includes error.message, 'this pull request'
  end

  private

  def compose(extra, comments: [])
    Shaka::ReviewReply.compose({ 'identity' => IDENTITY, 'summary' => 'Fixed the race.' }.merge(extra),
                               FakeReviews.new(comments))
  end

  def comment(url, body)
    { 'id' => url[/\d+\z/], 'html_url' => url, 'body' => body }
  end

  def later_table
    header = "| Commit | Reviewer | Model |\n| --- | --- | --- |"
    row = ->(model) { "| `aaaaaaa` | anthropic/claude | #{model} |" }
    "# Local Adversarial Review\n\n#{header}\n#{row['claude-opus-5-5']}\n\n#{header}\n#{row['forged-model']}\n\n" \
      "REVIEWED #{HEAD} BY anthropic/claude EFFORT high FINDINGS 0\n"
  end
end

# Records which comment lists a reply asked for, so an ordinary reply does no lookup.
class FakeReviews
  attr_reader :lookups

  def initialize(comments, pulls: [], reviews: {})
    @comments = comments
    @pulls = pulls
    @reviews = reviews
    @lookups = []
  end

  def repository = 'shakacode/shaka'
  def number = 284

  def issue_comments
    @lookups << :issues
    @comments
  end

  def api(path, **)
    @lookups << :api
    @pulls.find { |item| path.end_with?("/comments/#{item['id']}") } || {}
  end

  def review(id)
    @lookups << :review
    @reviews.fetch(id.to_s) { {} }
  end
end

# Discussion comments are fetched by id and must belong to this pull request.
class ReviewReplyLookupTest < Minitest::Test
  IDENTITY = ReviewReplyTest::IDENTITY

  def test_reads_inline_comments_and_pull_request_reviews
    discussion, review_url = lookup_urls
    github = FakeReviews.new([], pulls: [thread(discussion)], reviews: { '77' => note(review_url, 'Hosted review') })
    body = compose(github, [discussion, review_url])

    assert_includes body, "Addressed the [Thread note](#{discussion}) by UNKNOWN/UNKNOWN (UNKNOWN)"
    assert_includes body, "Addressed the [Hosted review](#{review_url}) by UNKNOWN/UNKNOWN (UNKNOWN)"
    assert_equal %i[api review], github.lookups
  end

  def test_refuses_a_discussion_comment_from_another_pull
    discussion = lookup_urls.first
    github = FakeReviews.new([], pulls: [thread(discussion, pull: 14)])
    error = assert_raises(Shaka::Error) { compose(github, [discussion]) }

    assert_includes error.message, 'not found'
  end

  private

  def lookup_urls
    ['https://github.com/shakacode/shaka/pull/284#discussion_r99',
     'https://github.com/shakacode/shaka/pull/284#pullrequestreview-77']
  end

  def thread(url, pull: 284)
    note(url, 'Thread note').merge('pull_request_url' => "https://api.github.com/repos/shakacode/shaka/pulls/#{pull}")
  end

  def note(url, heading)
    { 'id' => url[/\d+\z/], 'html_url' => url, 'body' => "# #{heading}\n\nplain\n" }
  end

  def compose(github, reviews)
    Shaka::ReviewReply.compose({ 'identity' => IDENTITY, 'summary' => 'Fixed the race.', 'reviews' => reviews },
                               github)
  end
end
