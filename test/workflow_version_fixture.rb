# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# Builds throwaway Git checkouts for the workflow version tests.
module WorkflowVersionFixture
  private

  def in_checkout
    Dir.mktmpdir do |dir|
      root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(root, 'skills/shaka'))
      File.write(File.join(root, 'skills/shaka/SKILL.md'), "skill\n")
      git(root, 'init', '-q')
      git(root, 'add', '.')
      git(root, '-c', 'user.name=t', '-c', 'user.email=t@example.com', 'commit', '-q', '-m', 'init')
      yield root, git(root, 'rev-parse', 'HEAD').strip
    end
  end

  def with_environment(values)
    saved = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  def git(root, *)
    output, status = Open3.capture2(Shaka::WorkflowVersion::GIT_ENVIRONMENT, TEST_GIT, '-C', root, *)
    assert_predicate status, :success?
    output
  end
end
