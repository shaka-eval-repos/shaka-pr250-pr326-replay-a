# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require_relative '../skills/shaka/lib/shaka/opening_publication'
require 'json'

class OpeningBrokenShebangTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Pull requests explain the outcome first.'

  def test_broken_unrelated_interpreter_does_not_stop_publication
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_broken_interpreter_safe(dir, root) }
    end
  end

  def test_script_with_candidate_sibling_is_rejected_without_alternate_gh
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_no_unsafe_gh_selected(dir, root) }
    end
  end

  def test_bare_direct_shebang_stops_before_publication
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_bare_shebang_rejected(dir, root) }
    end
  end

  def test_unrelated_relative_shebang_does_not_stop_publication
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_unrelated_relative_shebang_safe(dir, root) }
    end
  end

  def test_gh_wrapper_cannot_load_relative_file_from_candidate_checkout
    with_repository do |root|
      File.write(File.join(root, 'helper.rb'), "File.write(File.join(ENV.fetch('HOME'), 'candidate-executed'), '')\n")
      commit(root)
      Dir.mktmpdir { |dir| assert_gh_runs_outside_candidate(dir, root) }
    end
  end

  private

  def assert_gh_runs_outside_candidate(dir, root)
    output, error, status = Dir.chdir(root) do
      run_description(dir, root:) { |bin| install_relative_gh_wrapper(bin) }
    end
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
    refute_path_exists File.join(dir, 'candidate-executed')
  end

  def install_relative_gh_wrapper(bin)
    real = File.join(bin, 'gh-real')
    File.rename(File.join(bin, 'gh'), real)
    wrapper = "#!/bin/sh\n[ ! -f ./helper.rb ] || ruby ./helper.rb\nexec \"#{real}\" \"$@\"\n"
    File.write(File.join(bin, 'gh'), wrapper)
    File.chmod(0o755, File.join(bin, 'gh'))
  end

  def assert_unrelated_relative_shebang_safe(dir, root)
    output, error, status = run_description(dir, root:) do |bin|
      write_executable(bin, 'codex', 'exit 1')
      File.write(File.join(bin, 'codex'), "#!node\n")
    end
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
  end

  def assert_bare_shebang_rejected(dir, root)
    output, error, status = run_description(dir, root:) { |bin| File.write(File.join(bin, 'gh'), "#!node\n") }
    refute_predicate status, :success?, output
    assert_includes error, 'Relative shebang interpreter'
    refute_path_exists File.join(dir, 'published.md')
  end

  def assert_broken_interpreter_safe(dir, root)
    write_executable(dir, 'codex', 'exit 1')
    path = File.join(dir, 'codex')
    File.write(path, File.read(path).sub(/\A#![^\n]+/, '#!/nonexistent/shaka-interpreter'))
    output, error, status = run_description(dir, root:)
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
  end

  def assert_no_unsafe_gh_selected(dir, root)
    write_executable(dir, 'gh', fake_gh)
    write_executable(root, 'helper', 'exit 1')
    File.symlink(File.join(root, 'helper'), File.join(dir, 'helper'))
    with_only_path(dir) do
      selected = Shaka::OpeningPublication.with_safe_path(root:) { |_candidate, gh| gh }
      assert_nil selected
    end
  end

  def with_only_path(path)
    original = ENV.fetch('PATH')
    ENV['PATH'] = path
    yield
  ensure
    ENV['PATH'] = original
  end
end
