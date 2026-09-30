# frozen_string_literal: true

require_relative 'seam_initializer_test'

module SeamInitializerLayoutHelpers
  NEW_INVENTORY = %w[
    .agents .agents/shaka .agents/shaka.md .agents/shaka/bin .agents/shaka/bin/setup
    .agents/shaka/bin/test .agents/shaka/bin/validate .agents/shaka/config.yml
  ].freeze

  def agents_inventory(root)
    Dir.glob('.agents/**/*', File::FNM_DOTMATCH, base: root)
       .reject { |path| File.basename(path) == '.' }
       .push('.agents').sort
  end

  def init_with_probe(root)
    write_probe(root)
    init(root, setup_command: 'bin/probe', validate_command: 'bin/probe', test_command: 'bin/probe')
  end

  def write_probe(root)
    path = File.join(root, 'bin/probe')
    File.write(path, <<~SHELL)
      #!/bin/sh
      printf '%s\\n' "$PWD" "$@"
      [ "${1:-}" = fail ] && exit 23
      exit 0
    SHELL
    File.chmod(0o755, path)
  end

  def run_wrapper(checkout, name, *, chdir:)
    Open3.capture2e(File.join(checkout, '.agents/shaka/bin', name), *, chdir:)
  end

  def assert_runs_from(checkout, output, status, *arguments, exit_status: 0)
    assert_equal exit_status, status.exitstatus, output
    assert_equal [File.realpath(checkout), *arguments], output.lines.map(&:chomp)
  end

  def commit!(root)
    git!(root, 'add', '-A')
    git!(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
    Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD').first.strip
  end

  def assert_initialized(root)
    output, error, status = init(root)
    assert_predicate status, :success?, error
    assert_complete_seam(root, output)
  end

  def add_worktree(root)
    "#{root}-linked".tap { |linked| git!(root, 'worktree', 'add', '-q', linked) }
  end

  def seam_check(root, *)
    output, error, status = Open3.capture3(SeamInitializerTestHelpers::COMMAND, 'seam', 'check', '--root', root, *)
    assert_predicate status, :success?, error
    JSON.parse(output)
  end

  def write_file(root, relative, content = "#!/bin/sh\nexit 0\n", mode: 0o755)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(mode, path)
    path
  end

  def assert_refused_without_writes(root, *messages)
    before = agents_inventory(root)
    _output, error, status = init(root)

    refute_predicate status, :success?
    messages.each { |message| assert_includes error, message }
    assert_equal before, agents_inventory(root)
  end
end

class SeamInitializerNewLayoutTest < Minitest::Test
  include SeamInitializerTestHelpers
  include SeamInitializerLayoutHelpers

  def test_fresh_init_writes_exactly_the_new_layout
    with_repository do |root|
      output, error, status = init(root)

      assert_predicate status, :success?, error
      assert_equal NEW_INVENTORY, agents_inventory(root)
      assert_reports_new_paths(JSON.parse(output))
      assert_equal({ CONTRACT => 0o644, '.agents/shaka.md' => 0o644 }.merge(WRAPPERS.to_h { [it, 0o755] }),
                   GENERATED.to_h { [it, mode(root, it)] })
      assert_pointer_describes_new_layout(File.read(File.join(root, '.agents/shaka.md'), encoding: 'UTF-8'))
    end
  end

  def test_wrappers_run_at_the_repository_root_from_any_directory
    with_repository do |root|
      assert_predicate init_with_probe(root).last, :success?
      nested = FileUtils.mkdir_p(File.join(root, 'nested/deeper')).first

      %w[setup validate test].each do |name|
        assert_runs_from(root, *run_wrapper(root, name, 'space value', chdir: nested), 'space value')
      end
      output, status = run_wrapper(root, 'test', 'fail', chdir: Dir.tmpdir)
      assert_runs_from(root, output, status, 'fail', exit_status: 23)
    end
  end

  def test_wrappers_run_at_a_linked_worktree_root
    with_repository do |root|
      assert_predicate init_with_probe(root).last, :success?
      commit!(root)
      linked = add_worktree(root)
      FileUtils.mkdir_p(File.join(linked, 'nested'))

      output, status = run_wrapper(linked, 'validate', 'argument', chdir: File.join(linked, 'nested'))

      assert_runs_from(linked, output, status, 'argument')
    ensure
      FileUtils.rm_rf(linked) if linked
    end
  end

  def test_trusted_ref_reads_the_committed_new_layout
    with_repository do |root|
      assert_predicate init(root).last, :success?
      sha = commit!(root)

      local = seam_check(root, '--local')
      trusted = seam_check(root, '--ref', sha)

      assert_equal local.fetch('commands'), trusted.fetch('commands')
      assert_equal '.agents/shaka/config.yml', trusted.dig('paths', 'policy_configuration')
      assert_equal %w[trusted/ref true false],
                   trusted.fetch('validation').values_at('mode', 'grants_policy', 'grants_merge_authority').map(&:to_s)
    end
  end

  def test_repeat_init_refuses_to_overwrite_a_customized_configuration
    with_repository do |root|
      assert_predicate init(root).last, :success?
      path = File.join(root, '.agents/shaka/config.yml')
      customized = "#{File.read(path)}repo_prefix: CUSTOM\n"
      File.write(path, customized)

      _output, error, status = init(root)

      refute_predicate status, :success?
      assert_includes error, 'Refusing existing destination: .agents/shaka/config.yml'
      assert_equal customized, File.read(path)
    end
  end

  def test_init_in_a_linked_worktree_leaves_the_main_checkout_alone
    with_repository do |root|
      commit!(root)
      linked = add_worktree(root)
      output, error, status = init(linked)

      assert_predicate status, :success?, error
      assert_complete_seam(linked, output)
      refute_path_exists File.join(root, '.agents')
    ensure
      FileUtils.rm_rf(linked) if linked
    end
  end

  private

  def assert_reports_new_paths(report)
    assert_equal CONTRACT, report.dig('paths', 'policy_configuration')
    assert_equal WRAPPERS.sort, report.fetch('commands').values.sort
  end

  def assert_pointer_describes_new_layout(pointer)
    assert_includes pointer, '| `shaka/config.yml` |'
    assert_includes pointer, '| `shaka/bin/` |'
    refute_includes pointer, 'agent-workflow.yml'
    refute_match(/\#\{|%\{|\{\{/, pointer)
  end

  def mode(root, relative) = File.stat(File.join(root, relative)).mode & 0o777
end

class SeamInitializerExistingLayoutTest < Minitest::Test
  include SeamInitializerTestHelpers
  include SeamInitializerLayoutHelpers

  def test_legacy_configuration_points_to_the_upgrade
    with_repository do |root|
      write_file(root, '.agents/agent-workflow.yml', "version: 1\n", mode: 0o644)

      assert_refused_without_writes(root, '.agents/agent-workflow.yml', 'shaka seam upgrade')
    end
  end

  def test_both_layouts_are_refused
    with_repository do |root|
      write_file(root, '.agents/agent-workflow.yml', "version: 1\n", mode: 0o644)
      write_file(root, '.agents/shaka/config.yml', "version: 1\n", mode: 0o644)

      assert_refused_without_writes(root, 'Both .agents/agent-workflow.yml and .agents/shaka/config.yml exist')
    end
  end

  def test_legacy_command_without_configuration_is_a_partial_layout
    %w[.agents/bin/test .agents/bin/validate-local .agents/bin/validate_local].each do |relative|
      with_repository do |root|
        write_file(root, relative)

        assert_refused_without_writes(root, relative, '.agents/shaka/bin/')
      end
    end
  end

  def test_unrelated_agent_tools_stay_in_place
    with_repository do |root|
      tool = write_file(root, '.agents/bin/lint', "#!/bin/sh\necho lint\n")

      output, error, status = init(root)

      assert_predicate status, :success?, error
      assert_complete_seam(root, output)
      assert_equal "#!/bin/sh\necho lint\n", File.read(tool)
    end
  end

  def test_unsafe_new_layout_directories_are_refused
    { '.agents/shaka' => 'Refusing unsafe directory: .agents/shaka',
      '.agents/shaka/bin' => 'Refusing unsafe directory: .agents/shaka/bin' }.each do |relative, message|
      with_repository do |root|
        write_file(root, relative, "not a directory\n", mode: 0o644)

        assert_refused_without_writes(root, message)
      end
    end
  end

  # Break: a root Git cannot resolve gets wrappers that fail, or that run the outer project.
  def test_roots_that_are_not_a_git_worktree_root_are_refused
    with_repository do |root|
      FileUtils.rm_rf(File.join(root, '.git'))
      assert_refused_without_writes(root, 'Cannot identify repository root')
    end
    with_repository do |outer|
      root = FileUtils.mkdir_p(File.join(outer, 'nested')).first
      FileUtils.cp_r(File.join(outer, 'bin'), root)
      assert_refused_without_writes(root, '--root must be the Git worktree root')
    end
  end

  def test_permission_denial_writes_nothing_and_a_retry_succeeds
    skip 'chmod denial needs a non-root runner' if Process.uid.zero?

    with_repository do |root|
      directory = FileUtils.mkdir_p(File.join(root, '.agents/shaka')).first
      File.chmod(0o555, directory)
      assert_refused_without_writes(root, 'Permission denied for .agents/shaka/bin')

      File.chmod(0o755, directory)
      assert_initialized(root)
    ensure
      File.chmod(0o755, directory) if directory && File.directory?(directory)
    end
  end
end
