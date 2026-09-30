# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/workflow_version'

class WorkflowVersionMarkdownTest < Minitest::Test
  VERSION = Shaka::VERSION
  SHA = 'a' * 40

  def result(commit, modified: false, upstream: true)
    Shaka::WorkflowVersion::Result.new(version: VERSION, commit:, modified:, upstream:)
  end

  def test_a_known_commit_renders_as_a_link_without_the_version_number
    assert_equal "[`aaaaaaa`](https://github.com/shakacode/shaka/commit/#{SHA})", result(SHA).markdown
    assert_equal "[`aaaaaaa`](https://github.com/shakacode/shaka/commit/#{SHA}) (modified)",
                 result(SHA, modified: true).markdown
  end

  def test_a_sha256_commit_renders_as_a_link
    sha = 'b' * 64
    assert_equal "[`bbbbbbb`](https://github.com/shakacode/shaka/commit/#{sha})", result(sha).markdown
  end

  # A commit from a fork or an unrecognized source may not exist upstream, so it is not linked.
  def test_a_commit_from_another_source_shows_the_full_id_without_a_link
    assert_equal "`#{SHA}`", result(SHA, upstream: false).markdown
    assert_equal "`#{SHA}` (modified)", result(SHA, modified: true, upstream: false).markdown
  end

  def test_an_unknown_commit_falls_back_to_the_version_number
    assert_equal "`#{VERSION}` (commit unknown)", result(nil).markdown
    assert_equal "`#{VERSION}` (commit unknown, modified)", result(nil, modified: true).markdown
  end

  def test_any_installable_version_can_fall_back
    ['1.0.0+fork', "1.0.0-#{'x' * 60}"].each do |version|
      rendered = Shaka::WorkflowVersion::Result.new(version:, commit: nil, modified: false, upstream: false).markdown
      assert_equal "`#{version}` (commit unknown)", rendered
    end
  end

  def test_refuses_values_that_could_break_the_table
    assert_raises(Shaka::Error) { result("#{SHA} | x").markdown }
    assert_raises(Shaka::Error) { result("#{SHA} | x", upstream: false).markdown }
    assert_raises(Shaka::Error) do
      Shaka::WorkflowVersion::Result.new(version: "1.0\n| x", commit: nil, modified: false, upstream: false).markdown
    end
  end
end
