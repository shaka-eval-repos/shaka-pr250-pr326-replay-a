# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentWritersTest < Minitest::Test
  include CommentsFixture

  def test_many_outsiders_do_not_consume_individual_permission_lookups
    outside = (1..30).map { |id| comment(id: id, author: "outside#{id}", body: 'Noise') }
    maintainer = comment(id: 31, author: 'maintainer', body: 'Review this')
    result = packet(issue: outside + [maintainer], writers: ['maintainer'],
                    permissions: [permission('maintainer', 'write')])

    assert_equal ['Review this'], bodies(result, 'issue_comments')
    assert_equal 1, permission_call_count
    refute(@calls.any? { |argv, _| argv.join(' ').include?('collaborators?permission=push') })
  end

  def test_batched_nonwriter_is_marked_as_prefiltered
    outside = (1..9).map { |id| comment(id: id, author: "outside#{id}", body: 'Noise') }
    result = packet(issue: outside, writers: [])

    assert_true result['excluded_interactions'].first['prefiltered']
    assert_empty result['issue_comments']
  end

  def test_empty_public_pr_needs_no_writer_lookup
    result = packet

    assert_empty result['issue_comments']
    refute(@calls.any? { |argv, _| argv.join(' ').include?('/collaborators') })
  end

  def test_known_read_permission_is_not_marked_unavailable
    outside = comment(id: 33, author: 'outside', body: 'Feedback')
    result = packet(issue: [outside], permissions: [permission('outside', 'read')])

    assert_false result['excluded_interactions'].first['verification_unavailable']
    assert_false result['excluded_interactions'].first['prefiltered']
  end

  def test_unknown_direct_permission_is_marked_unavailable
    outside = comment(id: 34, author: 'outside', body: 'Feedback')
    result = packet(issue: [outside], permissions: [permission('outside', 'future_role')])

    assert_true result['excluded_interactions'].first['verification_unavailable']
    assert_false result['excluded_interactions'].first['prefiltered']
  end

  def test_unknown_batched_permission_stops_instead_of_prefiltering_author
    fields = (1..9).each_with_index.to_h do |id, index|
      role = id == 1 ? 'FUTURE_ROLE' : 'READ'
      ["u#{index}", { 'edges' => [{ 'node' => { 'login' => "person#{id}" }, 'permission' => role }] }]
    end
    github = client(response({ 'data' => { 'repository' => fields } }))
    logins = (1..9).map { |id| "person#{id}" }

    error = assert_raises(Shaka::Error) { Shaka::PublicComments::Writers.new(github).permissions(logins) }
    assert_match(/writer evidence is unavailable/, error.message)
  end

  def test_unavailable_batched_writer_evidence_blocks_public_packet
    commenters = (1..9).map { |id| comment(id: id, author: "person#{id}", body: 'Check this') }
    github = client(snapshot_response, repository_response('public'), response(commenters),
                    response([]), response([]), thread_response([]), response({}, status: 4))

    error = assert_raises(Shaka::Error) { comments_reader(github).call(expected_head: HEAD) }
    assert_match(/writer evidence is unavailable.*collaborator access/, error.message)
  end

  def test_mismatched_graphql_collaborator_cannot_grant_permission
    edge = { 'node' => { 'login' => 'another-user' }, 'permission' => 'WRITE' }
    fields = (0..8).to_h { |index| ["u#{index}", { 'edges' => [] }] }
    fields['u0'] = { 'edges' => [edge] }
    github = client(response({ 'data' => { 'repository' => fields } }))
    logins = (1..9).map { |id| "person#{id}" }

    error = assert_raises(Shaka::Error) { Shaka::PublicComments::Writers.new(github).permissions(logins) }
    assert_match(/writer evidence is unavailable/, error.message)
    assert_equal 1, @calls.length
  end

  def test_oversized_public_author_set_stops_before_external_lookup
    github = client
    logins = (1..501).map { |id| "person#{id}" }

    error = assert_raises(Shaka::Error) { Shaka::PublicComments::Writers.new(github).permissions(logins) }
    assert_match(/Too many public comment authors/, error.message)
    assert_empty @calls
  end

  def test_writer_confirmations_stop_at_one_hundred_candidates
    logins = (1..101).map { |id| "person#{id}" }
    pages = logins.each_slice(Shaka::PublicComments::Writers::BATCH_SIZE)
                  .map { |slice| graph_writer_response(slice, logins) }
    github = client(*pages)

    error = assert_raises(Shaka::Error) { Shaka::PublicComments::Writers.new(github).permissions(logins) }
    assert_match(/100 confirmations/, error.message)
    assert_equal 3, @calls.length
  end
end
