# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'

module SeamCheckHelpers
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  private

  def with_repository
    Dir.mktmpdir('shaka-seam') do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/bin'))
      write_commands(root)
      File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(config))
      yield root
    end
  end

  def write_commands(root)
    %w[setup validate test].each { |name| write_command(root, name) }
  end

  def write_command(root, name)
    path = File.join(root, '.agents/bin', name)
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
  end

  def config
    {
      'version' => 1, 'base_branch' => 'main',
      'review' => { 'required' => 'meaningful_changes', 'ci_review_jobs' => ['claude-review'],
                    'local_review_agents' => [{ 'provider' => 'anthropic', 'model_family' => 'claude' }] },
      'merge' => { 'preference' => 'auto' }
    }
  end

  def check_config(root, *)
    payload, error, status = capture_check(root, *)
    raise error unless status.success?

    payload
  end

  def capture_check(root, *)
    output, error, status = Open3.capture3(COMMAND, 'seam', 'check', '--root', root, *)
    payload = status.success? ? JSON.parse(output) : output
    [payload, error, status]
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
