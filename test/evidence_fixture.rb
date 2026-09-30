# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'json'
require 'tempfile'
require 'shaka/evidence/command'
require 'shaka/evidence/result'
require 'shaka/local_review'

module EvidenceFixture
  include RepositoryConfigTestHelpers

  def with_checkout
    with_repository do |root|
      system('git', '-C', root, 'init', '--quiet', exception: true)
      git(root, 'add', '-A')
      commit(root)
      yield root, git(root, 'rev-parse', 'HEAD')
    end
  end

  def git(root, *)
    output, error, status = Open3.capture3('git', '-C', root, *)
    assert_predicate status, :success?, error
    output.strip
  end

  def commit(root)
    git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
        'commit', '--quiet', '-m', 'candidate')
  end

  def run_check(root, ref, command: 'test', arguments: [], expected_exit: 0)
    output, _error = capture_io do
      assert_equal expected_exit, Shaka::Evidence::Command.run(
        ['run', '--root', root, '--ref', ref, '--repository', 'shakacode/shaka', '--command', command, *arguments]
      )
    end
    JSON.parse(output)
  end

  def bind(root, ref, head, result)
    Shaka::Evidence::Result.bind(result, root:, ref:, head:, repository: 'shakacode/shaka')
  end

  def review_check(root, ref)
    Tempfile.create(['shaka-review-evidence-', '.md']) do |report|
      report.write("Findings: none\nREVIEWED #{ref} BY openai/codex EFFORT medium FINDINGS 0\n")
      report.flush
      output, _error = capture_io do
        assert_equal 0, Shaka::LocalReview.run(review_arguments(root, ref, report.path))
      end
      JSON.parse(output)
    end
  end

  def review_arguments(root, ref, report)
    ['check', '--head', ref, '--reviewer', 'openai/codex', '--report', report,
     '--root', root, '--settings-ref', ref, '--repository', 'shakacode/shaka']
  end
end
