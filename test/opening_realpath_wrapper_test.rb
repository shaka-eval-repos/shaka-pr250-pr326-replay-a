# frozen_string_literal: true

# Rejects selected wrappers whose resolved directory links back into candidate code.

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'
require 'shaka/version'

class OpeningRealpathWrapperTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Pull requests explain the outcome first.'

  def test_gh_symlink_to_external_wrapper_with_candidate_helper_stops_publication
    with_repository do |root|
      add_candidate_helper(root)
      commit(root)
      Dir.mktmpdir { |dir| assert_gh_rejected(dir, root) }
    end
  end

  def test_git_symlink_to_external_wrapper_with_candidate_helper_skips_opening_check
    with_repository do |root|
      add_candidate_helper(root)
      commit(root)
      Dir.mktmpdir { |dir| assert_git_rejected(dir, root) }
    end
  end

  def test_dangling_link_beside_real_gh_wrapper_does_not_block_publication
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_dangling_link_safe(dir, root) }
    end
  end

  private

  def add_candidate_helper(root)
    File.write(File.join(root, 'helper.rb'), "File.write(File.join(ENV.fetch('HOME'), 'candidate-executed'), '')\n")
  end

  def assert_gh_rejected(dir, root)
    output, error, status = run_description(dir, root:) { |bin| link_gh_wrapper(bin, root) }
    refute_predicate status, :success?, output
    assert_includes error, 'gh wrapper directory contains candidate-backed links'
    refute_path_exists File.join(dir, 'published.md')
    refute_path_exists File.join(dir, 'candidate-executed')
  end

  def assert_git_rejected(dir, root)
    output, error, status = run_description(dir, root:, ref: true) { |bin| link_git_wrapper(bin, root) }
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
    assert_includes JSON.parse(output).dig('opening', 'reason'), 'git wrapper directory contains candidate-backed links'
    assert_includes File.read(File.join(dir, 'published.md')),
                    "| Workflow version | `#{Shaka::VERSION}` (commit unknown) |"
    refute_path_exists File.join(dir, 'candidate-executed')
  end

  def assert_dangling_link_safe(dir, root)
    output, error, status = run_description(dir, root:) { |bin| real_wrapper(bin, root, 'gh', link_candidate: false) }
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
  end

  def link_gh_wrapper(bin, root)
    real = real_wrapper(bin, root, 'gh')
    source = File.read(real).sub(/\A(#![^\n]+\n)/, "\\1require_relative 'helper'\n")
    File.write(real, source)
  end

  def link_git_wrapper(bin, root)
    real = real_wrapper(bin, root, 'git')
    File.write(real, "#!#{RbConfig.ruby}\nrequire_relative 'helper'\nexec #{TEST_GIT.inspect}, *ARGV\n")
    File.chmod(0o755, real)
  end

  def real_wrapper(bin, root, name, link_candidate: true)
    real_dir = File.join(bin, 'real')
    Dir.mkdir(real_dir)
    real = File.join(real_dir, name)
    File.rename(File.join(bin, name), real) if File.exist?(File.join(bin, name))
    File.symlink(File.join(real_dir, 'missing.rb'), File.join(real_dir, 'dangling.rb'))
    File.symlink(File.join(root, 'helper.rb'), File.join(real_dir, 'helper.rb')) if link_candidate
    File.symlink(real, File.join(bin, name))
    real
  end
end
