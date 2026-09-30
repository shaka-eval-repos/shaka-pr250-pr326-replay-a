# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'shaka/review_reply'

# The reply command fails a missing key before it asks GitHub for the review comment.
class ReviewReplyCommandTest < Minitest::Test
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def test_a_review_reply_without_a_key_does_not_call_github
    with_stub_gh do |dir, sentinel|
      status, error = reply_without_key(dir)
      refute_predicate status, :success?
      assert_includes error, 'key'
      refute_path_exists sentinel
    end
  end

  private

  def with_stub_gh
    Dir.mktmpdir do |dir|
      sentinel = File.join(dir, 'called')
      File.write(File.join(dir, 'gh'), "#!/bin/sh\ntouch #{sentinel}\nexit 1\n")
      File.chmod(0o755, File.join(dir, 'gh'))
      yield dir, sentinel
    end
  end

  def reply_without_key(dir)
    path = File.join(dir, 'content.json')
    reviews = ['https://github.com/owner/repo/pull/1#issuecomment-1']
    File.write(path, JSON.generate({ 'identity' => { 'agent' => 'Codex' }, 'summary' => 'Done.',
                                     'reviews' => reviews }))
    _output, error, status = Open3.capture3({ 'PATH' => "#{dir}:#{ENV.fetch('PATH')}" }, COMMAND, 'reply',
                                            'owner/repo', '1', '--content-file', path)
    [status, error]
  end
end

# A review URL has to name a comment on this pull request, and a list has to contain one.
class ReviewReplyListTest < Minitest::Test
  URL = 'https://github.com/shakacode/shaka/pull/284#issuecomment-1'

  def test_refuses_an_empty_review_list
    error = assert_raises(Shaka::Error) { compose([]) }

    assert_includes error.message, 'comment URL'
  end

  def test_refuses_a_comment_on_a_different_pull_request
    other = 'https://github.com/shakacode/shaka/pull/1#issuecomment-9'
    error = assert_raises(Shaka::Error) { compose([other]) }

    assert_includes error.message, 'this pull request'
  end

  private

  def compose(reviews)
    content = { 'identity' => { 'agent' => 'Codex' }, 'summary' => 'Fixed.', 'reviews' => reviews }
    github = Struct.new(:repository, :number).new('shakacode/shaka', 284)
    Shaka::ReviewReply.compose(content, github)
  end
end
