# frozen_string_literal: true

require_relative 'github_helper'
require 'shaka/public_comments'

module CommentsFixture
  include GitHubHelper

  def comment(id:, author:, body:)
    { 'id' => id, 'user' => { 'login' => author, 'type' => 'User' }, 'body' => body,
      'html_url' => "https://github.com/owner/repo/pull/42#issuecomment-#{id}" }
  end

  def packet(issue: [], reviews: [], inline: [], threads: [], **options)
    visibility = fixture_visibility(options)
    threads = default_threads(inline) if threads.empty?
    pages = options.fetch(:thread_pages) { [thread_response(threads)] }
    github = packet_client(visibility, [issue, reviews, inline], pages, options)
    Shaka::PublicComments::Reader.new(github, trust_config: options.fetch(:trust_config, empty_trust_config))
                                 .call(expected_head: HEAD)
  end

  def packet_client(visibility, items, pages, options)
    issue, reviews, inline = items
    responses = [snapshot_response, repository_response(visibility)]
    responses += comment_responses(issue, reviews, inline) + pages
    responses += prefilter_pages(visibility, options, issue + reviews + inline)
    responses += options.fetch(:permissions, []) + finish_context(visibility)
    client(*responses)
  end

  def empty_trust_config
    { users: Set.new, bots: Set.new, metadata_bots: Set.new, teams: [], sources: [] }
  end

  def comments_reader(github)
    Shaka::PublicComments::Reader.new(github, trust_config: empty_trust_config)
  end

  def default_threads(inline)
    inline.map { |item| thread(id: "T#{item['id']}", resolved: false, comments: [item['id']]) }
  end

  def finish_context(visibility)
    [snapshot_response, repository_response(visibility)]
  end

  def fixture_visibility(options)
    options.fetch(:visibility) { options.fetch(:private_repo, false) ? 'private' : 'public' }
  end

  def repository_response(visibility)
    response({ 'private' => visibility == 'private', 'visibility' => visibility })
  end

  def comment_responses(issue, reviews, inline)
    [response(issue), response(reviews), response(inline)]
  end

  def authors(items)
    items.filter_map do |item|
      user = item['user']
      user['login'] if user.is_a?(Hash) && user['type'] == 'User'
    end.uniq
  end

  def prefilter_pages(visibility, options, items)
    return [] unless visibility == 'public'

    logins = authors(items).select { |login| login.is_a?(String) && login.match?(Shaka::PublicComments::Writers::LOGIN) }
    return [] if logins.length <= Shaka::PublicComments::Writers::DIRECT_LIMIT

    writers = options.fetch(:writers, logins)
    logins.each_slice(Shaka::PublicComments::Writers::BATCH_SIZE).map { |slice| graph_writer_response(slice, writers) }
  end

  def graph_writer_response(logins, writers)
    fields = logins.each_with_index.to_h do |login, index|
      edges = writers.include?(login) ? [{ 'node' => { 'login' => login }, 'permission' => 'WRITE' }] : []
      ["u#{index}", { 'edges' => edges }]
    end
    response({ 'data' => { 'repository' => fields } })
  end

  def issue_packet(comments:, permissions: [])
    github = client(response({ 'number' => 42 }), repository_response('public'),
                    response(comments), *prefilter_pages('public', {}, comments), *permissions,
                    repository_response('public'))
    Shaka::PublicComments::Reader.new(github, trust_config: empty_trust_config).call(issue_only: true)
  end

  def bodies(result, key)
    result.fetch(key).map { |item| item['body'] }
  end

  def permission_call_count
    @calls.count { |argv, _| argv.join(' ').include?('/permission') }
  end

  def permission(login, level)
    response({ 'permission' => level, 'user' => { 'login' => login } })
  end

  def thread_response(threads, more: false, cursor: nil)
    connection = { 'nodes' => threads, 'pageInfo' => { 'hasNextPage' => more, 'endCursor' => cursor } }
    response({ 'data' => { 'repository' => { 'pullRequest' => { 'reviewThreads' => connection } } } })
  end

  def thread(id:, resolved:, comments:, more: false)
    { 'id' => id, 'isResolved' => resolved,
      'comments' => { 'nodes' => comments.map { |comment_id| { 'fullDatabaseId' => comment_id.to_s } },
                      'pageInfo' => { 'hasNextPage' => more } } }
  end

  def two_thread_pages
    [thread_response([thread(id: 'T1', resolved: true, comments: [50])], more: true, cursor: 'next'),
     thread_response([thread(id: 'T2', resolved: false, comments: [51])])]
  end

  def assert_inline_location(result, path:, original_line:, commit_id:)
    inline = result['inline_comments'].first
    assert_equal path, inline['path']
    assert_equal original_line, inline['original_line']
    assert_equal commit_id, inline['commit_id']
  end
end
