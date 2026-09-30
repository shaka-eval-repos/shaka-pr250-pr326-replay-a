# frozen_string_literal: true

# Proves trusted-config Git commands cannot load candidate-relative helper files.

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'

class OpeningGitCwdTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Pull requests explain the outcome first.'

  def test_trusted_config_git_wrapper_cannot_load_relative_file_from_candidate_checkout
    with_repository do |root|
      File.write(File.join(root, 'helper.rb'), "File.write(File.join(ENV.fetch('HOME'), 'candidate-executed'), '')\n")
      commit(root)
      Dir.mktmpdir { |dir| assert_git_runs_outside_candidate(dir, root) }
    end
  end

  private

  def assert_git_runs_outside_candidate(dir, root)
    output, error, status = Dir.chdir(root) do
      run_description(dir, root:, ref: true) { |bin| install_relative_git_wrapper(bin) }
    end
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
    refute_path_exists File.join(dir, 'candidate-executed')
  end

  def install_relative_git_wrapper(bin)
    wrapper = "#!/bin/sh\n[ ! -f ./helper.rb ] || ruby ./helper.rb\nexec \"#{TEST_GIT}\" \"$@\"\n"
    File.write(File.join(bin, 'git'), wrapper)
    File.chmod(0o755, File.join(bin, 'git'))
  end
end
