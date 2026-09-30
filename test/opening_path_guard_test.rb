# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../skills/shaka/lib/shaka/local_review/path_guard'

class OpeningPathGuardTest < Minitest::Test
  def test_drops_external_path_directory_with_candidate_executable_symlink
    with_candidate_link do |root, external, safe|
      path = Shaka::LocalReviewPathGuard.safe_path("#{external}:#{safe}", candidate_root: root,
                                                                          drop_candidate: true)
      assert_equal safe, path
      assert_raises(Shaka::Error) { Shaka::LocalReviewPathGuard.safe_path(external, candidate_root: root) }
    end
  end

  def test_uninspectable_external_directory_is_omitted_without_false_accusation
    with_candidate_link do |root, external, safe|
      with_uninspectable(external) do
        path = Shaka::LocalReviewPathGuard.safe_path("#{external}:#{safe}", candidate_root: root)
        assert_equal safe, path
      end
    end
  end

  def test_rejects_external_directory_with_unrelated_candidate_link
    with_candidate_link do |root, external, _safe|
      File.rename(File.join(external, 'gh'), File.join(external, 'project-tool'))
      assert_raises(Shaka::Error) { Shaka::LocalReviewPathGuard.safe_path(external, candidate_root: root) }
    end
  end

  def test_ignores_unsafe_wrapper_shadowed_by_safe_command
    with_candidate_link do |root, external, safe|
      File.unlink(File.join(external, 'gh'))
      write_script(File.join(root, 'node'), "#!/bin/sh\nexit 1\n")
      write_script(File.join(external, 'gh'), "#!#{root}/node\n")
      write_script(File.join(safe, 'gh'), "#!/bin/sh\nexit 0\n")
      path = "#{safe}:#{external}"
      assert_equal File.join(safe, 'gh'), Shaka::LocalReviewPathGuard.safe_executable(path, 'gh', root)
      assert_raises(Shaka::Error) { Shaka::LocalReviewPathGuard.safe_executable(external, 'gh', root) }
    end
  end

  def test_dropped_candidate_wrapper_does_not_hide_safe_command
    with_candidate_link do |root, external, safe|
      write_script(File.join(root, 'node'), "#!/bin/sh\nexit 1\n")
      write_script(File.join(root, 'gh'), "#!#{root}/node\n")
      write_script(File.join(safe, 'gh'), "#!/bin/sh\nexit 0\n")
      path = "#{external}:#{safe}"
      assert_equal safe, Shaka::LocalReviewPathGuard.safe_path(path, candidate_root: root, drop_candidate: true)
    end
  end

  def test_unsafe_env_split_string_fails_closed
    with_candidate_link do |root, external, _safe|
      File.unlink(File.join(external, 'gh'))
      ["#!/usr/bin/env -S 'FOO=1 node'", "#!/usr/bin/env -S PATH=#{root} node"].each do |shebang|
        write_script(File.join(external, 'gh'), "#{shebang}\n")
        assert_raises(Shaka::Error) { Shaka::LocalReviewPathGuard.safe_executable(external, 'gh', root) }
      end
    end
  end

  def test_relative_shebang_interpreter_fails_closed
    with_candidate_link do |root, external, _safe|
      File.unlink(File.join(external, 'gh'))
      ['#!./node', '#!/usr/bin/env ./node', '#!/usr/bin/env -S ./node'].each do |shebang|
        write_script(File.join(external, 'gh'), "#{shebang}\n")
        assert_raises(Shaka::Error) { Shaka::LocalReviewPathGuard.safe_executable(external, 'gh', root) }
      end
    end
  end

  private

  def write_script(path, body)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def with_uninspectable(directory)
    guarded = File.join(File.realpath(directory), 'gh')
    original = File.method(:symlink?)
    File.define_singleton_method(:symlink?) do |path|
      raise Errno::EACCES if path == guarded

      original.call(path)
    end
    yield
  ensure
    File.define_singleton_method(:symlink?, original)
  end

  def with_candidate_link
    Dir.mktmpdir do |dir|
      root, external, safe = %w[checkout external-bin safe-bin].map do |name|
        File.join(dir, name).tap { |path| Dir.mkdir(path) }
      end
      target = File.join(root, 'gh')
      File.write(target, "#!/bin/sh\nexit 1\n")
      File.chmod(0o755, target)
      File.symlink(target, File.join(external, 'gh'))
      yield File.realpath(root), external, safe
    end
  end
end
