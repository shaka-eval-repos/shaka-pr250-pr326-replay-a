# frozen_string_literal: true

require_relative 'github_helper'

class GitHubWalkthroughEvidenceTest < Minitest::Test
  include GitHubHelper

  # Catches a walkthrough that names no blob URL at the head for a changed path.
  def test_walkthrough_without_a_commit_pinned_changed_file_link_is_refused
    github = client(snapshot_response, files_response)
    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: 'A walkthrough.') }
    assert_includes error.message, 'commit-pinned'
    assert_equal 2, @calls.size
  end

  # Catches a blob link that points at the head but not at a path in the diff.
  def test_walkthrough_pin_to_an_unchanged_path_is_refused
    github = client(snapshot_response, files_response)
    body = "See https://github.com/owner/repo/blob/#{HEAD}/README.md."
    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: body) }
    assert_includes error.message, 'commit-pinned'
    assert_equal 2, @calls.size
  end

  # Catches README.md as a prefix of an unrelated README.md.old blob URL.
  def test_walkthrough_pin_that_only_prefixes_a_changed_path_is_refused
    github = client(snapshot_response, files_response(['README.md']))
    body = "See https://github.com/owner/repo/blob/#{HEAD}/README.md.old."
    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: body) }
    assert_includes error.message, 'commit-pinned'
    assert_equal 2, @calls.size
  end

  def test_walkthrough_pin_to_a_renamed_file_previous_path_is_accepted
    files = response([{ 'filename' => 'new.yml', 'previous_filename' => CHANGED_FILE }])
    github = client(snapshot_response, files, *gate_responses, html_response, review_response, review_response,
                    snapshot_response, response([]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)
    assert_equal 'COMMENTED', published['state']
  end

  # Catches a walkthrough that omits a completed review check visible on the PR.
  def test_walkthrough_omitting_a_completed_review_gate_is_refused
    github = client(snapshot_response, files_response, *gate_responses)
    error = assert_raises(Shaka::Error) do
      github.walkthrough(head: HEAD, body: "See #{PINNED_LINK}. Gates: validate.")
    end
    assert_includes error.message, 'claude-review'
    refute_includes error.message, 'validate'
    assert_equal 4, @calls.size
  end

  # Catches a required check that finished and is missing from the walkthrough.
  def test_walkthrough_omitting_a_completed_required_check_is_refused
    github = client(snapshot_response, files_response, *gate_responses)
    error = assert_raises(Shaka::Error) do
      github.walkthrough(head: HEAD, body: "See #{PINNED_LINK}. Gates: claude-review.")
    end
    assert_includes error.message, 'validate'
    assert_equal 4, @calls.size
  end

  def test_pending_review_checks_are_not_required_in_the_walkthrough
    body = "See #{PINNED_LINK}. Gates: validate."
    github = client(snapshot_response, files_response, *pending_review_gate_responses, html_response,
                    review_response(body: body), review_response(body: body), snapshot_response, response([]))
    assert_equal 'COMMENTED', github.walkthrough(head: HEAD, body: body)['state']
  end

  # Catches swallowing a required-check fetch failure as an empty gate list.
  def test_walkthrough_fails_when_required_check_evidence_is_unavailable
    github = client(snapshot_response, files_response, response({ 'message' => 'error' }))
    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: WALKTHROUGH) }
    assert_includes error.message, 'unavailable'
    assert_equal 3, @calls.size
  end

  # Catches omitting a skipped required check that merge still treats as terminal.
  def test_walkthrough_requires_a_skipped_required_check
    skipped = [{ 'name' => 'validate', 'state' => 'SKIPPED', 'bucket' => 'skipping' }]
    github = client(snapshot_response, files_response, response(skipped), response(skipped))
    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: "See #{PINNED_LINK}.") }
    assert_includes error.message, 'validate'
  end

  def test_walkthrough_pin_on_a_later_files_page_is_accepted
    page_one = (1..100).map { |index| "other/#{index}.txt" }
    github = client(snapshot_response, files_response(page_one), files_response, *gate_responses, html_response,
                    review_response, review_response, snapshot_response, response([]))
    published = github.walkthrough(head: HEAD, body: WALKTHROUGH)
    assert_equal 'COMMENTED', published['state']
  end

  # Catches a valid blob URL that ends a sentence with a period and no line anchor.
  def test_walkthrough_pin_followed_by_sentence_punctuation_is_accepted
    body = "See https://github.com/owner/repo/blob/#{HEAD}/#{CHANGED_FILE}. Gates: validate, claude-review."
    github = client(snapshot_response, files_response, *gate_responses, html_response,
                    review_response(body: body), review_response(body: body), snapshot_response, response([]))
    published = github.walkthrough(head: HEAD, body: body)
    assert_equal 'COMMENTED', published['state']
  end

  def test_walkthrough_pin_inside_angle_brackets_is_accepted
    body = "See <https://github.com/owner/repo/blob/#{HEAD}/#{CHANGED_FILE}>. Gates: validate, claude-review."
    github = client(snapshot_response, files_response, *gate_responses, html_response,
                    review_response(body: body), review_response(body: body), snapshot_response, response([]))
    published = github.walkthrough(head: HEAD, body: body)
    assert_equal 'COMMENTED', published['state']
  end

  def test_walkthrough_pin_to_a_path_with_a_plus_sign_is_accepted
    name = 'lib/a+b.rb'
    body = "See https://github.com/owner/repo/blob/#{HEAD}/#{name}. Gates: validate, claude-review."
    github = client(snapshot_response, files_response([name]), *gate_responses, html_response,
                    review_response(body: body), review_response(body: body), snapshot_response, response([]))
    published = github.walkthrough(head: HEAD, body: body)
    assert_equal 'COMMENTED', published['state']
  end

  def test_walkthrough_requires_a_cancelled_required_check
    cancelled = [{ 'name' => 'validate', 'state' => 'CANCELLED', 'bucket' => 'cancel' }]
    github = client(snapshot_response, files_response, response(cancelled), response(cancelled))
    error = assert_raises(Shaka::Error) { github.walkthrough(head: HEAD, body: "See #{PINNED_LINK}.") }
    assert_includes error.message, 'validate'
  end
end

class GitHubUnprotectedWalkthroughTest < Minitest::Test
  include GitHubHelper

  def test_walkthrough_on_an_unprotected_branch_cites_completed_optional_gates
    unprotected = ['', "no required checks reported on the 'main' branch\n", STATUS.new(1)]
    body = "See #{PINNED_LINK}. Gates: claude-review."
    github = client(snapshot_response, files_response, unprotected, *no_configured_requirements,
                    response(COMPLETED_GATES), html_response, review_response(body: body),
                    review_response(body: body), snapshot_response, response([]))
    published = github.walkthrough(head: HEAD, body: body)
    assert_equal 'COMMENTED', published['state']
  end
end

class GitHubSeamWalkthroughEvidenceTest < Minitest::Test
  include GitHubHelper

  # Catches a seam-declared required check that finished and is missing from the walkthrough.
  def test_walkthrough_omitting_a_completed_seam_required_check_is_refused
    empty = ['', "no required checks reported on the 'main' branch\n", STATUS.new(1)]
    head = [{ 'name' => 'checks', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    github = client(snapshot_response, files_response, empty, *no_configured_requirements, response(head),
                    response(head))
    error = assert_raises(Shaka::Error) do
      github.walkthrough(head: HEAD, body: "See #{PINNED_LINK}.", seam_required_checks: ['checks'])
    end
    assert_includes error.message, 'omits completed gates: checks'
  end
end
