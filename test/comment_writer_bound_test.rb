# frozen_string_literal: true

require_relative 'comments_fixture'

class CommentWriterBoundTest < Minitest::Test
  include CommentsFixture

  def test_exactly_one_hundred_writer_candidates_are_confirmed
    logins = (1..100).map { |id| "person#{id}" }
    graph = logins.each_slice(Shaka::PublicComments::Writers::BATCH_SIZE)
                  .map { |slice| graph_writer_response(slice, logins) }
    rest = logins.map { |login| permission(login, 'write') }
    result = Shaka::PublicComments::Writers.new(client(*graph, *rest)).permissions(logins)

    assert_equal(['write'], result.values.uniq)
    assert_equal 100, permission_call_count
  end
end
