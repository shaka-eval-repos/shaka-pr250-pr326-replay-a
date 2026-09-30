# frozen_string_literal: true

require_relative 'local_review_comment_test'
require 'shaka/local_review/ledger'

class LocalReviewBatchGuardsTest < Minitest::Test
  include LocalReviewCommentFixture

  def test_duplicate_reviewer_identity_is_case_insensitive
    first = round
    second = round(reviewer: 'OpenAI/Codex')
    error = assert_raises(Shaka::Error) { render('rounds' => [first, second]) }
    assert_includes error.message, 'same reviewer'
  end

  def test_same_head_peers_cannot_hide_an_unfixed_defect_with_the_same_id
    first = round(findings: [NIT.merge('class' => 'defect')])
    peer = round(reviewer: 'anthropic/claude', report: report(reviewer: 'anthropic/claude'))
    body = render('rounds' => [first, peer])
    assert_includes body, '1 unfixed defect'
    assert_equal 2, body.scan('**Dispositions**').size
  end

  def test_any_latest_batch_fix_requires_a_later_head
    first = round(findings: [NIT.merge('class' => 'defect', 'disposition' => 'fixed', 'commit' => EARLIER)])
    peer = round(reviewer: 'anthropic/claude', report: report(reviewer: 'anthropic/claude'))
    error = assert_raises(Shaka::Error) { render('rounds' => [first, peer]) }
    assert_includes error.message, 'no later round reviewed'
  end

  def test_repeated_noncontiguous_head_and_pending_publication_are_rejected
    assert_raises(Shaka::Error) { render('rounds' => [round, round(EARLIER), round]) }
    assert_raises(Shaka::Error) { render('rounds' => [round], 'pending' => [{ 'head' => HEAD }]) }
  end

  def test_stale_append_preserves_a_peer_write_and_checks_base
    with_ledger do |path|
      first = Shaka::LocalReviewLedger.new(path)
      stale = Shaka::LocalReviewLedger.new(path)
      stale.rounds
      first.append!(base: EARLIER, round: round)
      peer = round(reviewer: 'anthropic/claude', report: report(reviewer: 'anthropic/claude'))
      assert_equal 2, stale.append!(base: EARLIER, round: peer)
      assert_raises(Shaka::Error) { stale.append!(base: TRUSTED, round: peer) }
      assert_round_count(path, 2)
    end
  end

  def test_removed_reservation_rejects_stale_result
    with_ledger do |path|
      ledger = Shaka::LocalReviewLedger.new(path)
      ledger.start!(base: EARLIER, head: HEAD, reviewer: 'openai/codex')
      File.write(path, JSON.generate('base' => EARLIER, 'rounds' => [], 'pending' => []))
      error = assert_raises(Shaka::Error) { ledger.append!(base: EARLIER, round: round) }
      assert_includes error.message, 'reservation disappeared'
      assert_empty JSON.parse(File.read(path)).fetch('rounds')
    end
  end

  private

  def assert_round_count(path, count)
    assert_equal count, JSON.parse(File.read(path)).fetch('rounds').size
  end

  def with_ledger
    Dir.mktmpdir('batch-ledger') { |dir| yield File.join(dir, 'ledger.json') }
  end
end
