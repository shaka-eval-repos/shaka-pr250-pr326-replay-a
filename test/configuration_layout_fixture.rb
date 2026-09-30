# frozen_string_literal: true

require_relative 'repository_fixture'

module ConfigurationLayoutFixture
  include RepositoryConfigTestHelpers

  def with_new_layout
    Dir.mktmpdir('shaka-new-layout') do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/shaka/bin'))
      FileUtils.mkdir_p(File.join(root, '.agents/bin'))
      create_new_commands(root)
      File.write(File.join(root, '.agents/shaka/config.yml'), YAML.dump(config))
      yield root
    end
  end

  def create_new_commands(root)
    %w[setup validate test].each do |name|
      path = File.join(root, '.agents/shaka/bin', name)
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
  end

  def commit_fixture(root)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    system('git', '-C', root, 'add', '.', exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'layout fixture', exception: true)
  end

  def move_to_new_layout(root)
    FileUtils.mkdir_p(File.join(root, '.agents/shaka'))
    FileUtils.mv(File.join(root, '.agents/agent-workflow.yml'), File.join(root, '.agents/shaka/config.yml'))
    FileUtils.mv(File.join(root, '.agents/bin'), File.join(root, '.agents/shaka/bin'))
  end

  def move_to_legacy_layout(root)
    FileUtils.mv(File.join(root, '.agents/shaka/config.yml'), File.join(root, '.agents/agent-workflow.yml'))
    FileUtils.mv(File.join(root, '.agents/shaka/bin'), File.join(root, '.agents/bin/temporary'))
    FileUtils.mv(Dir.glob(File.join(root, '.agents/bin/temporary/*')), File.join(root, '.agents/bin'))
    FileUtils.rmdir(File.join(root, '.agents/bin/temporary'))
  end

  def write_new_prompt_config(root)
    path = File.join(root, '.agents/shaka/config.yml')
    policy = config.merge('review' => review_policy('prompt_file' => '.agents/shaka/review-prompt.md'))
    File.write(path, YAML.dump(policy))
    File.write(File.join(root, '.agents/shaka/review-prompt.md'), "Review instructions\n")
  end
end
