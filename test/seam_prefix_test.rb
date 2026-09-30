# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'yaml'

module SeamPrefixHelpers
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def with_repository(extra = {})
    Dir.mktmpdir('shaka-prefix') do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/bin'))
      %w[setup validate test].each do |name|
        path = File.join(root, '.agents/bin', name)
        File.write(path, "#!/bin/sh\nexit 0\n")
        File.chmod(0o755, path)
      end
      File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(config.merge(extra)))
      yield root
    end
  end

  def config
    {
      'version' => 1, 'base_branch' => 'main',
      'review' => { 'required' => 'meaningful_changes', 'ci_review_jobs' => ['claude-review'] },
      'merge' => { 'preference' => 'ask' }
    }
  end

  def check_config(root, *)
    output, error, status = Open3.capture3(COMMAND, 'seam', 'check', '--root', root, *)
    raise error unless status.success?

    JSON.parse(output)
  end

  def commit_repository(root)
    git!(root, 'init')
    git!(root, 'add', '.')
    git!(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', 'trusted')
  end

  def git!(root, *)
    output, status = Open3.capture2e('git', '-C', root, *)
    raise output unless status.success?
  end
end

class SeamPrefixTest < Minitest::Test
  include SeamPrefixHelpers

  def test_check_accepts_a_valid_repo_prefix
    with_repository('repo_prefix' => 'CPF') do |root|
      assert_equal 'CPF', check_config(root).fetch('repo_prefix')
    end
  end

  def test_check_omits_an_absent_repo_prefix
    with_repository do |root|
      refute check_config(root).key?('repo_prefix')
    end
  end

  def test_check_rejects_an_invalid_repo_prefix
    %w[cpf TOO_LONG A-B].each do |value|
      with_repository('repo_prefix' => value) do |root|
        _output, error, status = Open3.capture3(COMMAND, 'seam', 'check', '--root', root)
        refute_predicate status, :success?, value
        assert_includes error, 'repo_prefix'
      end
    end
  end

  def test_check_reads_repo_prefix_from_the_trusted_ref_not_the_candidate
    with_repository('repo_prefix' => 'TRUST') do |root|
      commit_repository(root)
      path = File.join(root, '.agents/agent-workflow.yml')
      File.write(path, File.read(path).sub('TRUST', 'DIRTY'))
      assert_equal 'TRUST', check_config(root, '--ref', 'HEAD').fetch('repo_prefix')
    end
  end

  def test_prefix_reads_a_trusted_ref_when_candidate_setup_is_missing
    with_repository('repo_prefix' => 'PLAN') do |root|
      commit_repository(root)
      FileUtils.rm(File.join(root, '.agents/bin/setup'))
      output, error, status = Open3.capture3(COMMAND, 'prefix', '--root', root, '--ref', 'HEAD')

      assert_predicate status, :success?, error
      assert_equal({ 'prefix' => 'PLAN', 'source' => 'seam' }, JSON.parse(output))
    end
  end

  def test_prefix_rejects_a_trusted_ref_that_omits_setup
    with_repository('repo_prefix' => 'PLAN') do |root|
      FileUtils.rm(File.join(root, '.agents/bin/setup'))
      commit_repository(root)
      _output, error, status = Open3.capture3(COMMAND, 'prefix', '--root', root, '--ref', 'HEAD')

      refute_predicate status, :success?
      assert_includes error, '.agents/bin/setup'
    end
  end

  def test_prefix_rejects_a_trusted_trigger_without_validate_local
    with_repository('repo_prefix' => 'PLAN') do |root|
      path = File.join(root, '.agents/bin/trigger-hosted-ci')
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
      commit_repository(root)
      _output, error, status = Open3.capture3(COMMAND, 'prefix', '--root', root, '--ref', 'HEAD')

      refute_predicate status, :success?
      assert_includes error, '.agents/bin/trigger-hosted-ci requires .agents/bin/validate-local'
    end
  end
end
