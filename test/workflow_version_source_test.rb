# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/workflow_version'

# Links only commits whose recorded source is shakacode/shaka, so a fork-only commit never 404s.
class WorkflowVersionSourceTest < Minitest::Test
  VERSION = Shaka::VERSION
  SHA = 'a' * 40

  def result(commit, upstream:)
    Shaka::WorkflowVersion::Result.new(version: VERSION, commit:, modified: false, upstream:)
  end

  def source(repository)
    { 'version' => VERSION, 'source' => { 'kind' => 'revision', 'revision' => SHA, 'repository' => repository } }
  end

  def test_an_installation_from_shakacode_shaka_is_upstream
    %w[https://github.com/shakacode/shaka git@github.com:shakacode/shaka.git
       https://github.com/shakacode/shaka.git ssh://git@github.com/shakacode/shaka.git
       ssh://github.com/shakacode/shaka.git].each do |repository|
      assert_equal result(SHA, upstream: true), Shaka::WorkflowVersion.current(identity: source(repository)), repository
    end
  end

  # Installation metadata is only type-checked, so a malformed commit falls back to unknown.
  def test_a_malformed_recorded_commit_falls_back_to_unknown
    [123, 'not-a-commit', "#{SHA} | x"].each do |bad|
      revision = { 'version' => VERSION, 'source' => { 'kind' => 'revision', 'revision' => bad } }
      development = { 'version' => VERSION, 'source' => { 'kind' => 'development', 'base_revision' => bad } }
      assert_nil Shaka::WorkflowVersion.current(identity: revision).commit, bad.inspect
      assert_nil Shaka::WorkflowVersion.current(identity: development).commit, bad.inspect
    end
  end

  def test_a_git_that_cannot_be_spawned_falls_back_to_unknown
    Dir.mktmpdir do |dir|
      git = File.join(dir, 'git')
      Dir.mkdir(git) # spawning a directory raises Errno::EACCES, not ENOENT
      identity = { 'version' => VERSION, 'source' => { 'kind' => 'uninstalled' } }
      assert_nil Shaka::WorkflowVersion.current(identity:, root: dir, git:).commit
    end
  end

  def test_an_installation_from_a_fork_or_unknown_source_is_not_upstream
    [nil, 'https://github.com/someone/shaka', 'git@github.com:shakacode/shaka-fork.git',
     'ssh://git@github.com/someone/shaka.git'].each do |repository|
      assert_equal result(SHA, upstream: false), Shaka::WorkflowVersion.current(identity: source(repository)),
                   repository.inspect
    end
  end
end
