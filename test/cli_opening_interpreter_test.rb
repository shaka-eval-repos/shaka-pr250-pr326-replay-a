# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require_relative 'cli_opening_check_fakes'
require 'json'

class CliOpeningInterpreterTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include CliOpeningCheckFakes

  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  ROOT = File.expand_path('..', __dir__)
  SUMMARY = 'Pull requests explain the outcome first.'

  def test_gh_wrapper_cannot_use_candidate_backed_interpreter
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_gh_interpreter_safe(dir, root, '#!/usr/bin/env node') }
    end
  end

  def test_env_split_string_rejects_path_assignment
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        assert_unsafe_interpreter_rejected(dir, root, "#!/usr/bin/env -S PATH=#{root} node",
                                           'env shebang sets environment variables')
      end
    end
  end

  def test_env_attached_split_string_names_interpreter
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_gh_interpreter_safe(dir, root, '#!/usr/bin/env -Snode') }
    end
  end

  def test_relative_env_interpreter_cannot_run_candidate_executable
    with_repository do |root|
      commit(root)
      Dir.mktmpdir do |dir|
        assert_unsafe_interpreter_rejected(dir, root, '#!/usr/bin/env ./node', 'gh interpreter uses a relative path')
      end
    end
  end

  def test_shell_wrapper_cannot_load_candidate_nonexecutable_helper
    with_repository do |root|
      commit(root)
      Dir.mktmpdir { |dir| assert_shell_helper_safe(dir, root) }
    end
  end

  private

  def assert_unsafe_interpreter_rejected(dir, root, shebang, message)
    external, = make_bins(dir)
    marker = File.join(dir, 'candidate-node-called')
    add_candidate_node(root, external, marker)
    output, error, status = run_description(external, root:) { |bin| use_env_node(bin, shebang) }
    refute_predicate status, :success?, output
    assert_includes error, message
    refute_path_exists marker
  end

  def assert_shell_helper_safe(dir, root)
    external, = make_bins(dir)
    marker = File.join(dir, 'candidate-helper-called')
    File.write(File.join(root, 'helper'), "File.write(#{marker.inspect}, '')")
    File.symlink(File.join(root, 'helper'), File.join(external, 'helper'))
    _output, _error, status = run_description(external, root:) do |bin|
      File.write(File.join(bin, 'gh'), "#!/bin/sh\nruby \"$(dirname \"$0\")/helper\"\n")
    end
    refute_predicate status, :success?
    refute_path_exists marker
    refute_path_exists File.join(external, 'published.md')
  end

  def assert_gh_interpreter_safe(dir, root, shebang)
    external, safe = make_bins(dir)
    marker = File.join(dir, 'candidate-node-called')
    add_candidate_node(root, external, marker)
    write_executable(safe, 'gh', fake_gh)
    with_path(safe) do
      assert_safe_publication(external, root, marker, shebang)
    end
  end

  def assert_safe_publication(external, root, marker, shebang)
    output, error, status = run_description(external, root:) { |bin| use_env_node(bin, shebang) }
    assert_predicate status, :success?, error
    assert_equal 'host_check', JSON.parse(output).dig('opening', 'status')
    assert_path_exists File.join(external, 'published.md')
    refute_path_exists marker
  end

  def make_bins(dir)
    %w[external safe].map { |name| File.join(dir, name).tap { |path| Dir.mkdir(path) } }
  end

  def add_candidate_node(root, external, marker)
    target = File.join(root, 'node')
    File.write(target, "#!/bin/sh\ntouch #{marker}\nexit 1\n")
    File.chmod(0o755, target)
    File.symlink(target, File.join(external, 'node'))
  end

  def use_env_node(bin, shebang)
    gh = File.join(bin, 'gh')
    File.write(gh, File.read(gh).sub(/\A#![^\n]+/, shebang))
  end

  def with_path(bin)
    original = ENV.fetch('PATH')
    ENV['PATH'] = "#{bin}:#{original}"
    yield
  ensure
    ENV['PATH'] = original
  end
end
