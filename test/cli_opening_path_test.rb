# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require_relative '../skills/shaka/lib/shaka/opening_publication'
require 'json'
require 'rbconfig'

class CliOpeningPathTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Pull requests explain the outcome first.'

  def test_candidate_git_on_path_is_ignored_before_publication
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_candidate_git_rejected(dir, root) }
    end
  end

  def test_direct_opening_publication_filters_candidate_git
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_direct_opening_safe(dir, root) }
    end
  end

  def test_symbolic_ref_cannot_grant_opening_settings
    with_repository do |root|
      commit(root)
      result = Shaka::OpeningPublication.new(root:, ref: 'HEAD').call(SUMMARY)
      assert_equal 'host_check', result.fetch('status')
      assert_includes result.fetch('reason'), 'full commit SHA'
    end
  end

  def test_unknown_checkout_root_stops_before_publication
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |dir|
        _output, error, status = run_description(dir, root:)
        refute_predicate status, :success?
        assert_includes error, 'Candidate checkout root is unknown'
        refute_path_exists File.join(dir, 'published.md')
      end
    end
  end

  def test_script_gh_beside_candidate_link_uses_safe_alternate
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_unrelated_candidate_link_safe(dir, root) }
    end
  end

  private

  def assert_unrelated_candidate_link_safe(dir, root)
    write_executable(root, 'project-tool', 'exit 1')
    File.symlink(File.join(root, 'project-tool'), File.join(dir, 'project-tool'))
    Dir.mktmpdir do |safe|
      write_executable(safe, 'gh', fake_gh)
      with_candidate_path(safe) { assert_safe_gh_publishes(dir, root) }
    end
  end

  def assert_safe_gh_publishes(dir, root)
    output, error, status = run_description(dir, root:)
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
    assert_path_exists File.join(dir, 'published.md')
  end

  def assert_candidate_git_rejected(dir, root)
    sha = fixture_ref(root)
    with_candidate_git(dir, root) do |trace|
      output, error, status = run_description(dir, root:, ref: sha)
      assert_predicate status, :success?, error
      assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
      refute_path_exists trace
      assert_path_exists File.join(dir, 'published.md')
    end
  end

  def assert_direct_opening_safe(dir, root)
    sha = Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD').first.strip
    with_candidate_git_link(dir, root) do |trace|
      result = Shaka::OpeningPublication.new(root:, ref: sha).call(SUMMARY)
      assert_equal 'host_check', result.fetch('status')
      refute_path_exists trace
    end
  end

  def with_candidate_git(dir, root)
    Dir.mkdir(bin = File.join(root, 'candidate-bin'))
    trace = File.join(dir, 'candidate-git-called')
    write_executable(bin, 'git', "File.write(#{trace.inspect}, '')")
    with_candidate_path(bin) { yield trace }
  end

  def with_candidate_git_link(dir, root)
    Dir.mkdir(bin = File.join(root, 'candidate-bin'))
    trace = File.join(dir, 'candidate-git-called')
    write_executable(bin, 'git', "File.write(#{trace.inspect}, '')")
    Dir.mkdir(external = File.join(dir, 'external-bin'))
    File.symlink(File.join(bin, 'git'), File.join(external, 'git'))
    with_candidate_path(external) { yield trace }
  end

  def with_candidate_path(bin)
    original = ENV.fetch('PATH')
    ENV['PATH'] = "#{bin}::#{original}"
    yield
  ensure
    ENV['PATH'] = original
  end
end
