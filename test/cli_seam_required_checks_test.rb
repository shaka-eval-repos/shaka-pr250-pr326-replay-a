# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'json'
require 'yaml'

# Proves `shaka pr --ref` gates on the trusted seam list, not the candidate file.
class CliSeamRequiredChecksTest < Minitest::Test
  include RepositoryConfigTestHelpers

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  # Answers only the requests `pr` makes on an unprotected branch; anything else fails the command.
  FAKE_GH = <<~RUBY
    #!/usr/bin/env ruby
    require 'json'
    args = ARGV.join(' ')
    pull = { 'headRefOid' => 'a' * 40, 'baseRefName' => 'main', 'baseRef' => { 'refUpdateRule' => nil } }
    case args
    when /\\Aapi graphql/ then puts JSON.generate('data' => { 'repository' => { 'pullRequest' => pull } })
    when /\\Apr checks .*--required/ then warn "no required checks reported on the 'main' branch"; exit 1
    when /\\Apr checks/ then puts JSON.generate([{ 'name' => 'checks', 'state' => 'SUCCESS', 'bucket' => 'pass' }])
    when %r{\\Aapi repos/owner/repo/rules/branches/main} then puts '[]'
    else warn "unexpected gh \#{args}"; exit 2
    end
  RUBY

  def test_pr_reports_trusted_seam_checks_when_github_requires_none
    with_repository('merge' => merge_policy.merge('required_checks' => ['checks'])) do |root|
      commit(root)
      drop_candidate_list(root)
      output, error, status = run_pr(root)

      assert_predicate status, :success?, error
      result = JSON.parse(output)
      assert_equal 'seam', result['requiredChecksSource']
      assert_equal(['checks'], result['requiredChecks'].map { |check| check['name'] })
    end
  end

  private

  def run_pr(root)
    bin = File.join(root, 'fake-bin')
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, 'gh'), FAKE_GH)
    File.chmod(0o755, File.join(bin, 'gh'))
    Open3.capture3({ 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" },
                   COMMAND, 'pr', 'owner/repo', '1', '--root', root, '--ref', 'HEAD')
  end

  def commit(root)
    [%w[init --quiet], %w[add .],
     %w[-c user.name=Test -c user.email=test@example.com commit --quiet -m trusted]].each do |args|
      system('git', '-C', root, *args, exception: true)
    end
  end

  def drop_candidate_list(root)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.safe_load_file(path)
    data['merge'].delete('required_checks')
    File.write(path, YAML.dump(data))
  end
end
