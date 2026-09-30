# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module RepositoryConfigTestHelpers
  def with_outside_validate_symlink(root)
    Dir.mktmpdir('outside-command') do |outside_root|
      outside = File.join(outside_root, 'validate')
      File.write(outside, "#!/bin/sh\n")
      path = File.join(root, '.agents/bin/validate')
      FileUtils.rm(path)
      File.symlink(outside, path)
      yield
    end
  end

  def merge_policy
    { 'preference' => 'auto' }
  end

  def with_repository(overrides = {})
    Dir.mktmpdir('shaka-repository-config') do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/bin'))
      create_commands(root)
      File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(seam(overrides)))
      yield root
    end
  end

  # A nil override removes the key, so a test can exercise an absent optional setting.
  def seam(overrides)
    config.merge(overrides).compact
  end

  def config
    {
      'version' => 1, 'base_branch' => 'main',
      'review' => review_policy,
      'merge' => merge_policy
    }
  end

  def create_commands(root)
    %w[setup validate test].each { |name| create_command(root, name) }
  end

  def create_command(root, name)
    filename = optional_commands.fetch(name, name).delete_prefix('.agents/bin/')
    path = File.join(root, '.agents/bin', filename)
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
  end

  def review_policy(overrides = {})
    { 'required' => 'meaningful_changes', 'ci_review_jobs' => ['claude-review'],
      'local_review_agents' => reviewers }.merge(overrides)
  end

  def reviewers
    [{ 'provider' => 'openai', 'model_family' => 'codex' },
     { 'provider' => 'anthropic', 'model_family' => 'claude' }]
  end

  def optional_commands
    { 'validate_local' => '.agents/bin/validate-local',
      'trigger_hosted_ci' => '.agents/bin/trigger-hosted-ci' }
  end
end
