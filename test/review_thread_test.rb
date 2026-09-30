# frozen_string_literal: true

require 'open3'
require_relative 'github_helper'

class ReviewThreadTest < Minitest::Test
  include GitHubHelper

  THREAD = 'PRRT_kwDOExample'
  SCRIPT = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def test_resolve_marks_an_unresolved_thread_after_this_account_replied
    github = client(user_response, thread_page, mutation_response(true))

    assert_equal({ 'thread_id' => THREAD, 'is_resolved' => true }, github.resolve_thread(THREAD))
    assert_equal %w[user graphql graphql], paths
    assert_includes sent(2)['query'], 'resolveReviewThread'
    assert_equal THREAD, sent(2).dig('variables', 'id')
  end

  def test_resolve_refuses_a_thread_this_account_only_opened
    github = client(user_response, thread_page(authors: ['justin808']))

    error = assert_raises(Shaka::Error) { github.resolve_thread(THREAD) }

    assert_includes error.message, 'replied'
    assert_equal %w[user graphql], paths
  end

  def test_resolve_refuses_a_thread_before_this_account_replied
    github = client(user_response, thread_page(authors: ['reviewer']))

    error = assert_raises(Shaka::Error) { github.resolve_thread(THREAD) }

    assert_includes error.message, 'replied'
    assert_equal %w[user graphql], paths
  end

  def test_resolve_refuses_an_already_resolved_thread
    github = client(user_response, thread_page(resolved: true))

    error = assert_raises(Shaka::Error) { github.resolve_thread(THREAD) }

    assert_includes error.message, 'already resolved'
    assert_equal %w[user graphql], paths
  end

  def test_resolve_refuses_a_thread_that_is_not_on_the_pull_request
    github = client(user_response, thread_page(id: 'PRRT_other'))

    error = assert_raises(Shaka::Error) { github.resolve_thread(THREAD) }

    assert_includes error.message, 'not on this pull request'
    assert_equal %w[user graphql], paths
  end

  def test_resolve_refuses_when_github_leaves_the_thread_unresolved
    github = client(user_response, thread_page, mutation_response(false))

    error = assert_raises(Shaka::Error) { github.resolve_thread(THREAD) }

    assert_includes error.message, 'did not resolve'
  end

  def test_resolve_refuses_a_malformed_thread_id_before_calling_github
    github = client

    error = assert_raises(Shaka::Error) { github.resolve_thread('not a thread') }

    assert_includes error.message, 'review-thread ID'
    assert_empty @calls
  end

  def test_resolve_refuses_when_reply_evidence_is_incomplete
    github = client(user_response, thread_page(authors: ['reviewer'], more_comments: true))

    error = assert_raises(Shaka::Error) { github.resolve_thread(THREAD) }

    assert_includes error.message, 'incomplete'
    assert_equal %w[user graphql], paths
  end

  def test_resolve_command_requires_a_thread_id
    output, status = Open3.capture2e(SCRIPT, 'resolve', 'owner/repo', '42')

    assert_equal 1, status.exitstatus
    assert_includes output, '--thread'
  end

  private

  def user_response = response({ 'login' => 'justin808' })

  def thread_page(id: THREAD, resolved: false, authors: %w[reviewer justin808], more_comments: false)
    response({ 'data' => { 'repository' => { 'pullRequest' => {
               'reviewThreads' => {
                 'nodes' => [thread_node(id, resolved, authors, more_comments)],
                 'pageInfo' => { 'hasNextPage' => false, 'endCursor' => nil }
               }
             } } } })
  end

  def thread_node(id, resolved, authors, more_comments)
    {
      'id' => id,
      'isResolved' => resolved,
      'comments' => {
        'nodes' => authors.map { |login| { 'author' => { 'login' => login } } },
        'pageInfo' => { 'hasNextPage' => more_comments }
      }
    }
  end

  def mutation_response(resolved)
    response({ 'data' => { 'resolveReviewThread' => {
               'thread' => { 'id' => THREAD, 'isResolved' => resolved }
             } } })
  end

  def paths
    @calls.map { |argv, _| argv.drop(2).find { |arg| !arg.start_with?('-') } }
  end

  def sent(index)
    JSON.parse(@calls.fetch(index).last)
  end
end
