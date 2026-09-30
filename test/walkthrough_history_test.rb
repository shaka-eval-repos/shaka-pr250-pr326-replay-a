# frozen_string_literal: true

require_relative 'github_helper'

module WalkthroughHistoryExamples
  include GitHubHelper

  OLD_SHA = 'b' * 40
  PRIOR = <<~BODY.freeze
    🤖 agent · provider · model · medium

    # Code Walkthrough

    The earlier behavior.

    _Walkthrough for commit `#{OLD_SHA}`. This is a COMMENT, not an approval._
  BODY
  CURRENT_URL = 'https://github.com/owner/repo/pull/42#pullrequestreview-123'

  private

  def review_record(id, body, login: 'ada', state: 'COMMENTED', submitted_at: '2026-09-24T07:00:00Z')
    { 'id' => id, 'node_id' => "PRR_#{id}", 'state' => state, 'body' => body,
      'submitted_at' => submitted_at, 'user' => { 'login' => login } }
  end

  def collapse_responses(source, stored)
    [review_response(body: source), html_response, review_response(body: source), graphql_response,
     review_response(body: stored)]
  end

  def collapsed(body)
    <<~TEXT
      #{Shaka::WalkthroughHistory::MARKER} #{CURRENT_URL}

      <details>
      <summary>Walkthrough for commit `#{OLD_SHA}`</summary>

      #{Shaka::WalkthroughText.archive(body.rstrip)}

      </details>
    TEXT
  end

  def publish_over(prior, *tail)
    github = client(*publish_responses(snapshot_response), response([prior]), response({ 'login' => 'ada' }), *tail)
    github.walkthrough(head: HEAD, body: WALKTHROUGH)
  end

  def assert_pointer_keeps(sentence)
    mutation = JSON.parse(graphql_call.last)
    assert_equal 'PRR_7', mutation.dig('variables', 'id')
    body = mutation.dig('variables', 'body')
    assert_includes body, "#{Shaka::WalkthroughHistory::MARKER} #{CURRENT_URL}"
    assert_includes body, sentence
    assert_includes body, "Walkthrough for commit `#{OLD_SHA}`"
  end

  def assert_archived_details_stay_text(body)
    visible = body.gsub(/^```.*?^```/m, '')
    assert_equal [1, 1], [visible.scan('<details>').size, visible.scan(%r{</details>}).size]
    assert_includes body, '&lt;details&gt;kept&lt;/details&gt;'
    assert_includes body, "```\n</details>\n```"
  end

  def assert_single_details_points_current
    body = JSON.parse(graphql_call.last).dig('variables', 'body')
    assert_equal 1, body.scan('<details>').size
    assert_includes body, CURRENT_URL
    assert_includes body, 'The earlier behavior.'
  end

  def graphql_response = response({ 'data' => { 'updatePullRequestReview' => { 'pullRequestReview' => {} } } })

  def graphql_call
    @calls.reverse.find { |_argv, stdin| stdin.include?('updatePullRequestReview') }
  end
end

class WalkthroughHistoryTest < Minitest::Test
  include GitHubHelper
  include WalkthroughHistoryExamples

  def test_an_earlier_walkthrough_by_the_author_points_at_the_new_review
    published = publish_over(review_record(7, PRIOR), *collapse_responses(PRIOR, collapsed(PRIOR)))

    assert_equal [7], published.dig('earlier_walkthroughs', 'collapsed')
    assert_empty published.dig('earlier_walkthroughs', 'left_intact')
    assert_pointer_keeps('The earlier behavior.')
  end

  def test_another_authors_walkthrough_stays_intact
    prior = review_record(7, PRIOR, login: 'other')
    github = client(*publish_responses(snapshot_response), response([prior]), response({ 'login' => 'ada' }))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_equal [7], published.dig('earlier_walkthroughs', 'left_intact')
    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    refute(@calls.any? { |_argv, stdin| stdin.include?('updatePullRequestReview') })
  end

  def test_an_independent_report_is_not_a_walkthrough
    report = review_record(7, "REVIEWED #{OLD_SHA} BY openai/codex\n")
    github = client(*publish_responses(snapshot_response), response([report]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_empty published.dig('earlier_walkthroughs', 'left_intact')
  end

  def test_a_walkthrough_that_quotes_an_attestation_is_still_collapsed
    quoted = PRIOR.sub('The earlier behavior.', "The earlier behavior.\n\nREVIEWED #{OLD_SHA} BY openai/codex")
    published = publish_over(review_record(7, quoted), *collapse_responses(quoted, collapsed(quoted)))

    assert_equal [7], published.dig('earlier_walkthroughs', 'collapsed')
  end

  def test_a_fenced_copy_inside_an_independent_report_stays_intact
    report = "Independent report.\n\n```\n#{PRIOR}```\n"
    github = client(*publish_responses(snapshot_response), response([review_record(7, report)]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_empty published.dig('earlier_walkthroughs', 'left_intact')
  end

  def test_a_newer_walkthrough_is_not_treated_as_earlier
    newer = review_record(9, PRIOR, submitted_at: '2026-09-24T09:00:00Z')
    github = client(*publish_responses(snapshot_response), response([newer]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
  end

  def test_a_human_edit_after_the_listing_is_the_body_that_gets_collapsed
    edited = PRIOR.sub('The earlier behavior.', 'A human edit.')
    publish_over(review_record(7, PRIOR), *collapse_responses(edited, collapsed(edited)))

    assert_includes JSON.parse(graphql_call.last).dig('variables', 'body'), 'A human edit.'
  end

  def test_a_body_that_changes_again_before_the_update_is_not_overwritten
    published = publish_over(review_record(7, PRIOR), review_response(body: PRIOR), html_response,
                             review_response(body: 'changed'))

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_includes published.dig('earlier_walkthroughs', 'unavailable').join, 'changed before collapse'
    refute(@calls.any? { |_argv, stdin| stdin.include?('updatePullRequestReview') })
  end

  def test_a_collapsed_walkthrough_without_a_url_is_reported
    damaged = "#{Shaka::WalkthroughHistory::MARKER} \n\n<details>\nkept\n</details>\n"
    published = publish_over(review_record(7, damaged), review_response(body: damaged))

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_includes published.dig('earlier_walkthroughs', 'unavailable').join, 'Review 7'
  end

  def test_a_walkthrough_that_already_points_at_the_current_review_is_left_alone
    prior = review_record(7, collapsed(PRIOR))
    github = client(*publish_responses(snapshot_response), response([prior]), response({ 'login' => 'ada' }),
                    review_response(body: collapsed(PRIOR)))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_equal(1, @calls.count { |argv, _| argv.include?('markdown') })
  end

  def test_a_superseded_walkthrough_is_retargeted_without_nesting_details
    earlier = collapsed(PRIOR).sub(CURRENT_URL, 'https://github.com/owner/repo/pull/42#pullrequestreview-9')
    publish_over(review_record(7, earlier), *collapse_responses(earlier, collapsed(PRIOR)))

    assert_single_details_points_current
  end

  def test_a_walkthrough_on_a_later_reviews_page_is_collapsed
    page = (1..100).map { |id| review_record(id, 'Approved.', state: 'APPROVED') }
    prior = review_record(101, PRIOR)
    github = client(*publish_responses(snapshot_response), response(page), response([prior]),
                    response({ 'login' => 'ada' }), *collapse_responses(PRIOR, collapsed(PRIOR)))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_equal [101], published.dig('earlier_walkthroughs', 'collapsed')
  end

  def test_a_failed_collapse_leaves_the_new_walkthrough_published
    github = client(*publish_responses(snapshot_response), response({}, status: 1))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_equal 'COMMENTED', published['state']
    assert_equal 123, published['id']
    refute_empty published.dig('earlier_walkthroughs', 'unavailable')
  end

  def test_a_readback_mismatch_is_reported_for_that_review_only
    prior = review_record(7, PRIOR)
    github = client(*publish_responses(snapshot_response), response([prior]), response({ 'login' => 'ada' }),
                    *collapse_responses(PRIOR, 'different'))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_includes published.dig('earlier_walkthroughs', 'unavailable').join, 'Review 7'
  end
end

class WalkthroughHistoryFooterTest < Minitest::Test
  include WalkthroughHistoryExamples

  def test_a_fenced_older_footer_does_not_label_the_summary
    older = 'c' * 40
    quoted = "_Walkthrough for commit `#{older}`. This is a COMMENT, not an approval._"
    fenced = PRIOR.sub("The earlier behavior.\n", "The earlier behavior.\n\n```\n#{quoted}\n```\n")
    publish_over(review_record(7, fenced), *collapse_responses(fenced, collapsed(fenced)))

    body = JSON.parse(graphql_call.last).dig('variables', 'body')
    assert_includes body, "<summary>Walkthrough for commit `#{OLD_SHA}`</summary>"
    refute_includes body, "<summary>Walkthrough for commit `#{older}`</summary>"
  end

  def test_a_details_tag_in_prose_cannot_close_the_archived_walkthrough
    noisy = PRIOR.sub('The earlier behavior.', "Uses <details>kept</details>.\n\n```\n</details>\n```\n")
    publish_over(review_record(7, noisy), *collapse_responses(noisy, collapsed(noisy)))

    assert_archived_details_stay_text(JSON.parse(graphql_call.last).dig('variables', 'body'))
  end

  def test_a_same_second_walkthrough_with_a_lower_id_is_earlier
    prior = review_record(7, PRIOR, submitted_at: '2026-09-24T08:00:00Z')
    published = publish_over(prior, *collapse_responses(PRIOR, collapsed(PRIOR)))

    assert_equal [7], published.dig('earlier_walkthroughs', 'collapsed')
  end

  def test_a_same_second_walkthrough_with_a_higher_id_stays
    prior = review_record(200, PRIOR, submitted_at: '2026-09-24T08:00:00Z')
    github = client(*publish_responses(snapshot_response), response([prior]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
  end

  def test_a_preamble_before_a_pasted_walkthrough_is_not_collapsed
    pasted = "Independent report.\n\n#{PRIOR}"
    github = client(*publish_responses(snapshot_response), response([review_record(7, pasted)]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_empty published.dig('earlier_walkthroughs', 'left_intact')
  end

  def test_a_review_that_stops_being_a_walkthrough_is_not_rewritten
    published = publish_over(review_record(7, PRIOR), review_response(body: "No longer a walkthrough.\n"))

    assert_empty published.dig('earlier_walkthroughs', 'collapsed')
    assert_includes published.dig('earlier_walkthroughs', 'unavailable').join, 'Review 7'
    refute(@calls.any? { |_argv, stdin| stdin.include?('updatePullRequestReview') })
  end
end
