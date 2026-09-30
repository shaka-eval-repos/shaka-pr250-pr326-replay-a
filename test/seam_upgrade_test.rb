# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'support/seam_upgrade_fixture'

class SeamUpgradePreviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_preview_is_read_only_and_classifies_references
    with_repository do |root|
      add_references(root)
      before = [git!(root, 'status', '--porcelain=v1', '-z'), git!(root, 'ls-files', '--stage')]
      preview = report(root)
      assert_equal before, [git!(root, 'status', '--porcelain=v1', '-z'), git!(root, 'ls-files', '--stage')]
      assert_preview(preview)
    end
  end

  def add_references(root)
    FileUtils.mkdir_p(File.join(root, '.github/workflows'))
    File.write(File.join(root, '.github/workflows/ci.yml'), 'run: .agents/bin/test')
    File.write(File.join(root, 'CHANGELOG.md'), 'Previously .agents/bin/test')
    commit_fixture(root, 'references')
  end

  def assert_preview(preview)
    assert_equal 'ready', preview.fetch('status')
    assert_move_and_repairs(preview)
    assert_reference_kinds(preview)
  end

  def assert_move_and_repairs(preview)
    moves = preview.fetch('moves').to_h { |item| [item.fetch('from'), item.fetch('to')] }
    assert_equal '.agents/shaka/config.yml', moves.fetch('.agents/agent-workflow.yml')
    assert_includes preview.fetch('repairs').map { |item| item.fetch('kind') }, 'recognized shell root discovery'
  end

  def assert_reference_kinds(preview)
    kinds = preview.fetch('references').to_h { |item| [item.fetch('path'), item.fetch('kind')] }
    assert_equal 'tracked CI', kinds.fetch('.github/workflows/ci.yml')
    assert_equal 'historical', kinds.fetch('CHANGELOG.md')
  end

  def test_unrelated_edits_are_allowed_and_overlapping_edits_block
    with_repository do |root|
      File.write(File.join(root, 'notes.txt'), 'unrelated')
      assert_equal 'ready', report(root).fetch('status')
      File.open(File.join(root, '.agents/bin/setup'), 'a') { |file| file.write("# edited\n") }
      assert_blocker(root, 'overlapping checkout edit')
      assert_equal 'unrelated', File.read(File.join(root, 'notes.txt'))
    end
  end

  def test_existing_private_destination_blocks_without_overwrite
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/shaka'))
      File.write(File.join(root, '.agents/shaka/config.yml'), 'private')
      assert_blocker(root, 'partial migration')
      assert_equal 'private', File.read(File.join(root, '.agents/shaka/config.yml'))
    end
  end

  def test_ignored_private_destination_still_blocks_layout_upgrade
    with_repository do |root|
      File.open(File.join(root, '.git/info/exclude'), 'a') { |file| file.puts('/.agents/shaka/') }
      FileUtils.mkdir_p(File.join(root, '.agents/shaka'))
      File.write(File.join(root, '.agents/shaka/config.yml'), 'private')
      assert_blocker(root, 'partial migration')
      assert_equal 'private', File.read(File.join(root, '.agents/shaka/config.yml'))
    end
  end

  def test_ambiguous_custom_root_blocks
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nroot=$(custom_dirname \"$0\")/../..\nexit 0\n")
      commit_fixture(root, 'ambiguous')
      assert_blocker(root, 'ambiguous repository-root')
    end
  end

  def assert_blocker(root, phrase)
    preview = report(root)
    assert_equal 'blocked', preview.fetch('status')
    assert(preview.fetch('blockers').any? { |message| message.include?(phrase) })
  end
end

class SeamUpgradeLateReviewFixTest < Minitest::Test
  include SeamUpgradeFixture

  def test_indexed_segmented_path_hidden_by_unstaged_edit_blocks
    with_repository do |root|
      path = File.join(root, 'ci.rb')
      File.write(path, 'system(File.join(".agents", "bin", "test"))')
      commit_fixture(root, 'indexed segmented path')
      File.write(path, 'puts "safe"')
      assert_includes report(root).fetch('blockers').join, 'indexed segmented old-layout reference'
    end
  end

  def test_shell_continued_command_path_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nexec .agents/bi\\\nn/test\n")
      commit_fixture(root, 'continued command path')
      assert_includes report(root).fetch('blockers').join, 'continued old-layout reference'
    end
  end

  def test_moved_command_with_segmented_old_path_blocks
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nexec \".agents\"/bin/test\n")
      commit_fixture(root, 'moved segmented command')
      assert_includes report(root).fetch('blockers').join, 'old command path'
    end
  end

  def test_moved_command_with_continued_old_path_blocks
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nexec .agents/bi\\\nn/test\n")
      commit_fixture(root, 'moved continued command')
      assert_includes report(root).fetch('blockers').join, 'old command path'
    end
  end

  def test_moved_config_with_segmented_old_path_blocks
    with_repository do |root|
      path = File.join(root, '.agents/agent-workflow.yml')
      File.open(path, 'a') { |file| file.write("# File.join('.agents', 'bin', 'test')\n") }
      commit_fixture(root, 'moved segmented configuration')
      assert_includes report(root).fetch('blockers').join, 'old layout reference in moved configuration'
    end
  end

  def test_temporary_write_failure_removes_owned_file_and_restores
    with_repository do |root|
      error = assert_raises(Shaka::Error) { run_failing_writer(root) }
      assert_includes error.message, 'restored'
      assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
      refute_path_exists Shaka::Seam::Upgrader.journal_path(root)
      refute_predicate Dir.glob(File.join(root, '.agents/**/*.shaka-upgrade-tmp')), :any?
    end
  end

  def run_failing_writer(root)
    digest = report(root).fetch('digest')
    failing_writer.new(['--root', root, '--apply', '--digest', digest]).run
  end

  def failing_writer
    Class.new(Shaka::Seam::Upgrader) do
      private

      def write_temp_file(tmp, state)
        return super if @injected

        @injected = true
        super(tmp, state.merge('mode' => nil))
      end
    end
  end
end

class SeamUpgradeCleanupReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_continued_directory_name_in_tracked_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nexec .age\\\nnts/bin/test\n")
      commit_fixture(root, 'continued layout directory')
      assert_includes report(root).fetch('blockers').join, 'continued old-layout reference'
    end
  end

  def test_computed_path_with_repeated_separator_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nexec \u0024ROOT//.agents/bin/test\n")
      commit_fixture(root, 'repeated computed separator')
      assert_includes report(root).fetch('blockers').join, 'old'
    end
  end

  def test_variable_alias_to_legacy_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nagent_dir=.agents\nexec \"\u0024agent_dir/bin/test\"\n")
      commit_fixture(root, 'legacy directory alias')
      assert_includes report(root).fetch('blockers').join, 'aliased old-layout directory'
    end
  end

  def test_workflow_environment_alias_to_legacy_command_blocks
    with_repository do |root|
      path = File.join(root, '.github/workflows/ci.yml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "env:\n  AGENT_DIR: .agents\nsteps:\n  - run: \u0024AGENT_DIR/bin/test\n")
      commit_fixture(root, 'workflow directory alias')
      assert_blocked_with(root, 'aliased old-layout directory')
    end
  end

  def test_variable_alias_with_shell_separator_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nagent_dir=.agents; exec \"\u0024agent_dir/bin/test\"\n")
      commit_fixture(root, 'same-line legacy directory alias')
      assert_includes report(root).fetch('blockers').join, 'aliased old-layout directory'
    end
  end

  def test_external_tracked_symlink_blocks
    with_repository do |root, parent|
      File.write(File.join(parent, 'shared-ci.sh'), "#!/bin/sh\nexec .agents/bin/test\n")
      File.symlink('../shared-ci.sh', File.join(root, 'ci.sh'))
      commit_fixture(root, 'external CI symlink')
      assert_includes report(root).fetch('blockers').join, 'external symlink target cannot be verified'
    end
  end

  def test_undecodable_indexed_segmented_command_blocks
    with_repository do |root|
      path = File.join(root, 'ci.sh')
      File.binwrite(path, "#!/bin/sh\n# \xFF\nexec \".agents\"/bin/test\n".b)
      commit_fixture(root, 'indexed undecodable segmented command')
      File.write(path, "#!/bin/sh\nexit 0\n")
      assert_includes report(root).fetch('blockers').join, 'undecodable indexed old-layout reference'
    end
  end

  def test_recovery_finishes_validated_upgrade_when_journal_delete_fails
    with_repository do |root|
      journal = Shaka::Seam::Upgrader.journal_path(root)
      run_with_failed_journal_delete(root, journal)
      assert File.file?(File.join(root, '.agents/shaka/config.yml'))
      refute_path_exists File.join(root, '.agents/agent-workflow.yml')
      assert_equal 'completed', report(root, '--recover').fetch('status')
      assert File.file?(File.join(root, '.agents/shaka/config.yml'))
      refute_path_exists journal
    end
  end

  def test_journal_directory_sync_failure_stops_before_worktree_writes
    with_repository do |root|
      digest = report(root).fetch('digest')
      assert_raises(Errno::EIO) do
        failing_journal_sync.new(['--root', root, '--apply', '--digest', digest]).run
      end
      assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
      refute_path_exists File.join(root, '.agents/shaka/config.yml')
      assert_equal 'restored', report(root, '--recover').fetch('status')
    end
  end

  def failing_journal_sync
    Class.new(Shaka::Seam::Upgrader) do
      private

      def fsync_journal_directory = raise(Errno::EIO)
    end
  end

  def run_with_failed_journal_delete(root, journal)
    digest = report(root).fetch('digest')
    assert_raises(Errno::EACCES) do
      failing_cleanup_upgrader.new(['--root', root, '--apply', '--digest', digest]).run
    end
    assert File.file?(journal)
  end

  def failing_cleanup_upgrader
    Class.new(Shaka::Seam::Upgrader) do
      private

      def delete_journal = raise(Errno::EACCES)
    end
  end
end

class SeamUpgradeRealUseReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_unmarked_old_root_from_this_repository_is_repaired
    with_repository do |root|
      source = File.read(File.expand_path('../.agents/bin/setup', __dir__))
      write_wrapper(root, 'setup', source)
      commit_fixture(root, 'unmarked version-one wrapper')
      preview = report(root)
      assert_equal 'ready', preview.fetch('status')
      assert_includes preview.fetch('repairs').map { |item| item.fetch('kind') }, 'recognized shell root discovery'
    end
  end

  def test_ignored_old_directory_tool_blocks_without_reading_it
    with_repository do |root|
      File.write(File.join(root, '.gitignore'), ".agents/bin/private-tool\n")
      tool = File.join(root, '.agents/bin/private-tool')
      File.write(tool, "#!/bin/sh\nexec \"$(dirname \"\u00240\")/test\"\n")
      commit_fixture(root, 'ignored private tool')
      assert_includes report(root).fetch('blockers').join, 'untracked old-directory tool'
      assert File.file?(tool)
    end
  end

  def test_directory_alias_with_trailing_slash_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nagent_dir=.agents/\nexec \"\u0024agent_dir/bin/test\"\n")
      commit_fixture(root, 'slash-suffixed legacy directory alias')
      assert_includes report(root).fetch('blockers').join, 'aliased old-layout directory'
    end
  end

  def test_dot_prefixed_directory_alias_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nagent_dir=./.agents\nexec \"\u0024agent_dir/bin/test\"\n")
      commit_fixture(root, 'dot-prefixed legacy directory alias')
      assert_includes report(root).fetch('blockers').join, 'aliased old-layout directory'
    end
  end

  def test_computed_directory_alias_blocks
    with_repository do |root|
      source = "#!/bin/sh\nagent_dir=\u0024ROOT/.agents\nexec \"\u0024agent_dir/bin/test\"\n"
      File.write(File.join(root, 'ci.sh'), source)
      commit_fixture(root, 'computed legacy directory alias')
      assert_includes report(root).fetch('blockers').join, 'aliased old-layout directory'
    end
  end

  def test_parameter_expansion_directory_alias_blocks
    with_repository do |root|
      source = "#!/bin/sh\nagent_dir=\u0024{agent_dir:-.agents}\nexec \"\u0024agent_dir/bin/test\"\n"
      File.write(File.join(root, 'ci.sh'), source)
      commit_fixture(root, 'parameter-expanded legacy directory alias')
      assert_includes report(root).fetch('blockers').join, 'aliased old-layout directory'
    end
  end
end

class SeamUpgradeHiddenIndexReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_assume_unchanged_hiding_indexed_old_command_blocks
    with_repository do |root|
      path = File.join(root, 'ci.sh')
      File.write(path, "#!/bin/sh\nexec .agents/bin/test\n")
      commit_fixture(root, 'indexed old command')
      File.write(path, "#!/bin/sh\nexit 0\n")
      git!(root, 'update-index', '--assume-unchanged', 'ci.sh')
      assert_includes report(root).fetch('blockers').join, 'index flag hides checkout edits'
    end
  end

  def test_skip_worktree_hiding_indexed_old_command_blocks
    with_repository do |root|
      path = File.join(root, 'ci.sh')
      File.write(path, "#!/bin/sh\nexec .agents/bin/test\n")
      commit_fixture(root, 'indexed old command')
      File.write(path, "#!/bin/sh\nexit 0\n")
      git!(root, 'update-index', '--skip-worktree', 'ci.sh')
      assert_includes report(root).fetch('blockers').join, 'index flag hides checkout edits'
    end
  end

  def test_quoted_shell_fragment_inside_directory_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nexec .age\"nts\"/bin/test\n")
      commit_fixture(root, 'fragmented legacy directory')
      assert_includes report(root).fetch('blockers').join, 'fragmented old-layout reference'
    end
  end

  def test_escaped_character_inside_legacy_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nexec .agents/bin/tes\\t\n")
      commit_fixture(root, 'escaped legacy command')
      assert_includes report(root).fetch('blockers').join, 'fragmented old-layout reference'
    end
  end
end

class SeamUpgradeApplyTest < Minitest::Test
  include SeamUpgradeFixture

  def test_apply_preserves_arguments_working_directory_exit_status_and_policy_source
    with_repository do |root, parent|
      add_pointer(root)
      before = probe_results(root, '.agents/bin/setup', parent)
      assert_equal 'applied', apply_upgrade(root).fetch('status')
      assert_equal before, probe_results(root, '.agents/shaka/bin/setup', parent)
      assert_moved_layout(root)
      assert_policy_sources(root)
    end
  end

  def add_pointer(root)
    File.write(File.join(root, '.agents/shaka.md'), 'Run .agents/bin/validate and read .agents/agent-workflow.yml')
    commit_fixture(root, 'pointer')
  end

  def probe_results(root, command, parent)
    path = File.join(root, command)
    [%w[one two], %w[fail]].map do |arguments|
      output, _error, status = Open3.capture3(path, *arguments, chdir: parent)
      [normalized_output(output), status.exitstatus]
    end
  end

  def assert_moved_layout(root)
    assert_equal 'version: 1', File.read(File.join(root, '.agents/shaka/config.yml')).lines.first.strip
    assert File.executable?(File.join(root, '.agents/shaka/bin/setup'))
    assert_equal 'Run .agents/shaka/bin/validate and read .agents/shaka/config.yml',
                 File.read(File.join(root, '.agents/shaka.md'))
    assert_equal 'already_upgraded', report(root).fetch('status')
  end

  def assert_policy_sources(root)
    sha = git!(root, 'rev-parse', 'HEAD').strip
    output, error, status = Open3.capture3(COMMAND, 'seam', 'check', '--root', root, '--ref', sha)
    assert_predicate status, :success?, error
    paths = JSON.parse(output).fetch('paths')
    assert_equal '.agents/agent-workflow.yml', paths.fetch('policy_configuration')
    assert_equal '.agents/shaka/config.yml', paths.fetch('candidate_configuration')
  end

  def test_linked_worktree_uses_its_own_root
    with_repository do |root, parent|
      linked = File.join(parent, 'linked')
      git!(root, 'worktree', 'add', '-q', '-b', 'fixture-linked', linked)
      apply_upgrade(linked)
      output, error, status = Open3.capture3(File.join(linked, '.agents/shaka/bin/setup'), 'linked', chdir: parent)
      assert_predicate status, :success?, error
      assert_equal "#{File.realpath(linked)}\nlinked\n", output
    end
  end

  def test_generated_wrapper_ignores_git_environment_from_hook
    with_repository do |root, parent|
      apply_upgrade(root)
      environment = { 'GIT_DIR' => '/tmp/missing-git-dir', 'GIT_WORK_TREE' => '/tmp/missing-worktree',
                      'GIT_CEILING_DIRECTORIES' => File.realpath(root) }
      path = File.join(root, '.agents/shaka/bin/setup')
      output, error, status = Open3.capture3(environment, path, 'one', chdir: parent)
      assert_predicate status, :success?, error
      assert_equal "#{File.realpath(root)}\none\n", normalized_output(output)
    end
  end

  def test_safe_relative_symlink_keeps_its_target
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate')
      File.delete(path)
      File.symlink('../../bin/probe', path)
      commit_fixture(root, 'link')
      assert_equal '../../../bin/probe', report(root).fetch('symlinks').first.fetch('new_target')
      apply_upgrade(root)
      assert_equal '../../../bin/probe', File.readlink(File.join(root, '.agents/shaka/bin/validate'))
    end
  end

  def test_external_symlink_is_refused
    with_repository do |root, parent|
      external = File.join(parent, 'outside')
      File.write(external, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, external)
      path = File.join(root, '.agents/bin/validate')
      File.delete(path)
      File.symlink(external, path)
      assert_equal 'blocked', report(root).fetch('status')
    end
  end

  def test_custom_shell_root_is_repaired
    with_repository do |root|
      write_wrapper(root, 'setup', custom_shell_wrapper)
      commit_fixture(root, 'custom')
      repairs = report(root).fetch('repairs')
      assert_includes repairs.map { |item| item.fetch('kind') }, 'custom shell root discovery'
    end
  end

  def custom_shell_wrapper
    "#!/bin/sh\nset -eu\nroot=$(dirname \"$0\")/../..\ncd \"$root\"\nexec \"$root/bin/probe\" \"$@\"\n"
  end
end

class SeamUpgradeRecoveryTest < Minitest::Test
  include SeamUpgradeFixture

  def test_interrupted_apply_restores_known_files_and_keeps_unrelated_edits
    with_repository do |root|
      journal = write_journal(root, plan_for(root))
      create_moved_config(root, journal)
      File.write(File.join(root, 'notes.txt'), 'keep this')
      assert_equal 'recovery_required', report(root).fetch('status')
      assert_equal 'restored', report(root, '--recover').fetch('status')
      assert_equal 'keep this', File.read(File.join(root, 'notes.txt'))
      assert_legacy_root_restored(root)
    end
  end

  def create_moved_config(root, journal)
    moved = File.join(root, '.agents/shaka/config.yml')
    FileUtils.mkdir_p(File.dirname(moved))
    File.binwrite(moved, journal.fetch('desired').fetch('.agents/shaka/config.yml').fetch('data').unpack1('m0'))
  end

  def test_recovery_preserves_later_user_edit
    with_repository do |root|
      write_journal(root, plan_for(root))
      File.write(File.join(root, '.agents/bin/setup'), 'later user edit')
      _output, error, status = upgrade(root, '--recover')
      refute_predicate status, :success?
      assert_includes error, 'changed after interruption'
      assert_equal 'later user edit', File.read(File.join(root, '.agents/bin/setup'))
    end
  end

  def test_recovery_preserves_unexpected_temporary_file
    with_repository do |root|
      write_journal(root, plan_for(root))
      temporary = File.join(root, '.agents/agent-workflow.yml.shaka-upgrade-tmp')
      File.write(temporary, 'later user file')
      _output, error, status = upgrade(root, '--recover')
      refute_predicate status, :success?
      assert_includes error, 'changed after interruption'
      assert_equal 'later user file', File.read(temporary)
    end
  end

  def test_ordinary_failure_rolls_back
    with_repository do |root|
      File.write(File.join(root, 'notes.txt'), 'untouched')
      error = attempt_failing_upgrade(root)
      assert_includes error.message, 'restored'
      assert_equal 'untouched', File.read(File.join(root, 'notes.txt'))
      assert_legacy_root_restored(root)
      refute_path_exists Shaka::Seam::Upgrader.journal_path(root)
    end
  end

  def test_failure_preserves_preexisting_empty_layout_directories
    with_repository do |root|
      directory = File.join(root, '.agents/shaka/bin')
      FileUtils.mkdir_p(directory)
      attempt_failing_upgrade(root)
      assert Dir.exist?(directory)
      assert Dir.empty?(directory)
    end
  end

  def failing_upgrader
    Class.new(Shaka::Seam::Upgrader) do
      private

      def write_state(relative, state)
        @writes = (@writes || 0) + 1
        raise Errno::EIO, 'injected failure' if @writes == 2

        super
      end
    end
  end

  def attempt_failing_upgrade(root)
    digest = report(root).fetch('digest')
    assert_raises(Shaka::Error) { failing_upgrader.new(['--root', root, '--apply', '--digest', digest]).run }
  end

  def test_permission_denial_then_retry
    skip 'chmod denial needs a non-root runner' if Process.uid.zero?

    with_repository do |root|
      directory = File.join(root, '.agents')
      File.chmod(0o555, directory)
      assert_denied_then_restore(root, directory)
      assert_equal 'applied', apply_upgrade(root).fetch('status')
    end
  end

  def assert_denied_then_restore(root, directory)
    assert_permission_denied(root)
  ensure
    File.chmod(0o755, directory)
  end

  def assert_permission_denied(root)
    _output, error, status = upgrade(root, '--apply', '--digest', report(root).fetch('digest'))
    refute_predicate status, :success?
    assert_includes error, 'Permission denied'
    assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
    refute_path_exists Shaka::Seam::Upgrader.journal_path(root)
  end

  def assert_legacy_root_restored(root)
    assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
    refute_path_exists File.join(root, '.agents/shaka/config.yml')
  end
end

class SeamUpgradeVariantsTest < Minitest::Test
  include SeamUpgradeFixture

  def test_optional_commands_move_and_unrelated_tool_stays
    with_repository do |root|
      add_optional_commands(root)
      moves = report(root).fetch('moves').map { |item| item.fetch('from') }
      assert_includes moves, '.agents/bin/trigger-hosted-ci'
      apply_upgrade(root)
      assert_optional_files(root)
    end
  end

  def add_optional_commands(root)
    write_wrapper(root, 'validate-local')
    write_wrapper(root, 'trigger-hosted-ci')
    File.write(File.join(root, '.agents/bin/formatter'), "#!/bin/sh\nexit 0\n")
    commit_fixture(root, 'optional')
  end

  def assert_optional_files(root)
    assert File.file?(File.join(root, '.agents/shaka/bin/validate-local'))
    assert File.file?(File.join(root, '.agents/bin/formatter'))
  end

  def test_existing_new_command_blocks_without_duplicate_contract
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/shaka/bin'))
      File.write(File.join(root, '.agents/shaka/bin/setup'), 'private')
      preview = report(root)
      assert_equal 'blocked', preview.fetch('status')
      assert_includes preview.fetch('blockers').join, 'destination already exists'
      assert_equal 'private', File.read(File.join(root, '.agents/shaka/bin/setup'))
    end
  end

  def test_broken_existing_new_layout_is_not_a_successful_noop
    with_repository do |root|
      apply_upgrade(root)
      File.delete(File.join(root, '.agents/shaka/bin/setup'))
      preview = report(root)
      assert_equal 'blocked', preview.fetch('status')
    end
  end

  def test_custom_ruby_root_repair_preserves_execution
    with_repository do |root, parent|
      write_wrapper(root, 'setup', ruby_wrapper("File.expand_path('../..', __dir__)"))
      commit_fixture(root, 'ruby-root')
      before = ruby_result(root, '.agents/bin/setup', parent)
      assert_ruby_repair(root)
      apply_upgrade(root)
      assert_equal before, ruby_result(root, '.agents/shaka/bin/setup', parent)
      environment = { 'GIT_DIR' => '/tmp/missing-git-dir', 'GIT_CEILING_DIRECTORIES' => File.realpath(root) }
      assert_equal before, ruby_result(root, '.agents/shaka/bin/setup', parent, environment)
    end
  end

  def ruby_result(root, command, parent, environment = {})
    output, error, status = Open3.capture3(environment, File.join(root, command), 'arg', chdir: parent)
    [output, error, status.exitstatus]
  end

  def assert_ruby_repair(root)
    kinds = report(root).fetch('repairs').map { |item| item.fetch('kind') }
    assert_includes kinds, 'custom Ruby root discovery'
  end

  def ruby_wrapper(root_expression)
    "#!/usr/bin/env ruby\nroot = #{root_expression}\nDir.chdir(root) { puts ARGV.join(':') }\nexit 17\n"
  end

  def test_shell_root_without_exit_on_error_is_blocked
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nroot=$(dirname \"$0\")/../..\ncd \"$root\"\n")
      commit_fixture(root, 'no-errexit')
      preview = report(root)
      assert_equal 'blocked', preview.fetch('status')
      assert_includes preview.fetch('blockers').join, 'ambiguous repository-root'
    end
  end

  def test_generated_root_without_exit_on_error_is_blocked
    with_repository do |root|
      script = "#!/bin/sh\n# Generated by shaka seam init.\n#{SeamUpgradeFixture::ROOT_LINE}\n" \
               "cd \"$root\"\nexec \"$root/bin/probe\" \"$@\"\n"
      write_wrapper(root, 'setup', script)
      commit_fixture(root, 'generated without errexit')
      assert_includes report(root).fetch('blockers').join, 'ambiguous repository-root'
    end
  end

  def test_shell_root_with_late_or_disabled_exit_on_error_is_blocked
    with_repository do |root|
      root_line = 'root=$(dirname "$0")/../..'
      ["#{root_line}\nset -e\n", "set -e\nset +e\n#{root_line}\n"].each do |body|
        write_wrapper(root, 'setup', "#!/bin/sh\n#{body}cd \"$root\"\n")
        commit_fixture(root, 'unsafe-errexit')
        assert_equal 'blocked', report(root).fetch('status')
        assert_includes report(root).fetch('blockers').join, 'ambiguous repository-root'
      end
    end
  end
end

class SeamUpgradeReviewFixTest < Minitest::Test
  include SeamUpgradeFixture

  def test_prefix_collisions_are_not_rewritten_but_live_ci_is
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      File.write(path, "run: .agents/bin/test-e2e\nrun: .agents/bin/test\n")
      commit_fixture(root, 'ci')
      apply_upgrade(root)
      assert_equal "run: .agents/bin/test-e2e\nrun: .agents/shaka/bin/test\n", File.read(path)
    end
  end

  def test_live_internal_reference_is_rewritten_and_historical_line_is_kept
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, 'internal/ci'))
      File.write(File.join(root, 'internal/ci/run.yml'), 'run: .agents/bin/test')
      File.write(File.join(root, 'CHANGELOG.md'), 'Previously .agents/bin/test')
      commit_fixture(root, 'references')
      apply_upgrade(root)
      assert_reference_contents(root)
    end
  end

  def assert_reference_contents(root)
    assert_equal 'run: .agents/shaka/bin/test', File.read(File.join(root, 'internal/ci/run.yml'))
    assert_equal 'Previously .agents/bin/test', File.read(File.join(root, 'CHANGELOG.md'))
  end

  def test_reference_to_unmoved_optional_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'README.md'), 'Run .agents/bin/validate-local')
      commit_fixture(root, 'reference')
      preview = report(root)
      assert_equal 'blocked', preview.fetch('status')
      assert_includes preview.fetch('blockers').join, 'unmoved path'
    end
  end

  def test_pathname_root_keeps_its_type
    with_repository do |root, parent|
      write_wrapper(root, 'setup', pathname_wrapper)
      commit_fixture(root, 'pathname')
      before = ruby_execution(root, '.agents/bin/setup', parent)
      apply_upgrade(root)
      assert_equal before, ruby_execution(root, '.agents/shaka/bin/setup', parent)
    end
  end

  def pathname_wrapper
    "#!/usr/bin/env ruby\nrequire 'pathname'\nroot = Pathname(__dir__).parent.parent\n" \
      "Dir.chdir(root) { puts (root / 'bin/probe').exist? }\nexit 7\n"
  end

  def ruby_execution(root, command, parent)
    output, error, status = Open3.capture3(File.join(root, command), chdir: parent)
    [output, error, status.exitstatus]
  end

  def test_pipefail_without_errexit_blocks_shell_repair
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nset -o pipefail\nroot=$(dirname \"$0\")/../..\n")
      commit_fixture(root, 'pipefail')
      assert_includes report(root).fetch('blockers').join, 'ambiguous repository-root'
    end
  end

  def test_apply_rejects_digest_from_earlier_preview
    with_repository do |root|
      digest = report(root).fetch('digest')
      File.write(File.join(root, 'README.md'), 'Run .agents/bin/test')
      commit_fixture(root, 'new-reference')
      _output, error, status = upgrade(root, '--apply', '--digest', digest)
      refute_predicate status, :success?
      assert_includes error, 'inputs changed'
      assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
    end
  end

  def test_candidate_supplied_journal_does_not_trigger_recovery
    with_repository do |root|
      File.write(File.join(root, '.agents/.shaka-upgrade-journal.json'), 'forged')
      assert_equal 'ready', report(root).fetch('status')
    end
  end

  def test_recovery_refuses_symlink_parent_escape
    with_repository do |root, parent|
      File.symlink(parent, File.join(root, 'evil'))
      write_hostile_journal(root)
      _output, error, status = upgrade(root, '--recover')
      refute_predicate status, :success?
      assert_includes error, 'symlink parent'
      refute_path_exists File.join(parent, 'outside')
    end
  end

  def write_hostile_journal(root)
    entry = 'evil/outside'
    original = { entry => { 'type' => 'file', 'mode' => 0o644, 'data' => ['key'].pack('m0') } }
    desired = { entry => { 'type' => 'absent' } }
    journal = { 'version' => 1, 'original' => original, 'desired' => desired,
                'temporary' => ["#{entry}.shaka-upgrade-tmp"], 'created_directories' => [] }
    File.write(Shaka::Seam::Upgrader.journal_path(root), JSON.generate(journal))
  end
end

class SeamUpgradeSecondReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_apply_with_existing_journal_fails_without_mutation
    with_repository do |root|
      digest = report(root).fetch('digest')
      write_journal(root, plan_for(root))
      _output, error, status = upgrade(root, '--apply', '--digest', digest)
      refute_predicate status, :success?
      assert_includes error, 'Interrupted upgrade'
      assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
    end
  end

  def test_existing_temporary_file_is_preserved
    with_repository do |root|
      temporary = File.join(root, '.agents/agent-workflow.yml.shaka-upgrade-tmp')
      File.write(temporary, 'user file')
      _output, error, status = upgrade(root, '--apply', '--digest', report(root).fetch('digest'))
      refute_predicate status, :success?
      assert_includes error, 'Existing upgrade temporary file'
      assert_equal 'user file', File.read(temporary)
      refute_path_exists Shaka::Seam::Upgrader.journal_path(root)
    end
  end

  def test_vendored_path_is_not_rewritten
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      File.write(path, 'run: vendor/tool/.agents/bin/test')
      commit_fixture(root, 'vendor')
      apply_upgrade(root)
      assert_equal 'run: vendor/tool/.agents/bin/test', File.read(path)
    end
  end

  def test_mode_flags_are_checked
    with_repository do |root|
      digest = report(root).fetch('digest')
      [['--digest', digest], ['--apply'], ['--apply', '--recover', '--digest', digest]].each do |flags|
        _output, _error, status = upgrade(root, *flags)
        refute_predicate status, :success?
      end
    end
  end

  def test_apply_on_already_upgraded_layout_is_a_noop
    with_repository do |root|
      apply_upgrade(root)
      assert_equal 'already_upgraded', apply_upgrade(root).fetch('status')
    end
  end

  def test_symlink_to_another_moved_command_keeps_target
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate')
      File.delete(path)
      File.symlink('test', path)
      commit_fixture(root, 'linked-command')
      apply_upgrade(root)
      assert_equal 'test', File.readlink(File.join(root, '.agents/shaka/bin/validate'))
    end
  end

  def test_tracked_executable_reference_blocks
    with_repository do |root|
      path = File.join(root, 'run-ci')
      File.write(path, "#!/bin/sh\nexec .agents/bin/test \"$@\"\n")
      File.chmod(0o755, path)
      commit_fixture(root, 'executable-reference')
      assert_includes report(root).fetch('blockers').join, 'executable old-path reference'
    end
  end

  def test_python_shebang_in_sh_directory_is_unsupported
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/opt/sh/bin/python3\nprint('hello')\n")
      commit_fixture(root, 'python command')
      assert_includes report(root).fetch('blockers').join, 'unsupported command language'
    end
  end

  def test_zsh_and_ksh_scripts_need_explicit_repair
    %w[zsh ksh].each do |shell|
      with_repository do |root|
        write_wrapper(root, 'setup', "#!/bin/#{shell}\nexit 0\n")
        commit_fixture(root, 'shell command')
        assert_includes report(root).fetch('blockers').join, 'unsupported command language'
      end
    end
  end

  def test_ruby_program_name_dependency_blocks
    with_repository do |root|
      script = "#!/usr/bin/env ruby\nroot = File.expand_path('../..', __dir__)\nputs $PROGRAM_NAME\n"
      write_wrapper(root, 'setup', script)
      commit_fixture(root, 'Ruby invocation dependency')
      assert_includes report(root).fetch('blockers').join, 'invocation-relative dependency'
    end
  end

  def test_symlinked_legacy_command_directory_blocks
    with_repository do |root|
      FileUtils.mv(File.join(root, '.agents/bin'), File.join(root, 'old-bin'))
      File.symlink('../old-bin', File.join(root, '.agents/bin'))
      assert_includes report(root).fetch('blockers').join, 'expected a real directory'
    end
  end
end

class SeamUpgradeReferenceSafetyTest < Minitest::Test
  include SeamUpgradeFixture

  def test_dynamic_and_absolute_references_block_without_touching_files
    with_repository do |root|
      path = File.join(root, '.github/workflows/ci.yml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, dynamic_references)
      commit_fixture(root, 'dynamic paths')
      assert_blocked_with(root, 'dynamic old-path reference')
      assert_includes File.read(path), '${root}/.agents/bin/test'
    end
  end

  def test_root_relative_and_url_references_block
    references = ['[setup](/.agents/bin/setup)', '`/.agents/bin/test`',
                  'https://github.com/o/r/blob/main/.agents/bin/test']
    assert_each_reference_blocks(references)
  end

  def test_each_computed_prefix_blocks_individually
    assert_each_reference_blocks(dynamic_references.lines.map(&:strip))
  end

  def assert_each_reference_blocks(lines)
    lines.each do |line|
      with_repository do |root|
        path = File.join(root, 'README.md')
        File.write(path, line)
        commit_fixture(root, 'reference')
        assert_blocked_with(root, 'dynamic old-path reference')
      end
    end
  end

  def dynamic_references
    <<~TEXT
      run: ${root}/.agents/bin/test
      run: ${{ github.workspace }}/.agents/bin/test
      run: $TOOL_HOME/.agents/bin/test
      run: "$TOOL_HOME"/.agents/bin/test
      run: /repo/.agents/bin/test
    TEXT
  end

  def test_moved_script_with_sibling_dependency_blocks
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nset -eu\n. \"$(dirname \"$0\")/common.sh\"\n")
      commit_fixture(root, 'sibling dependency')
      assert_blocked_with(root, 'invocation-relative dependency')
    end
  end

  def test_inbound_symlink_to_moved_command_blocks
    with_repository do |root|
      File.symlink('../.agents/bin/test', File.join(root, 'bin/test'))
      commit_fixture(root, 'inbound link')
      assert_blocked_with(root, 'symlink targets moved')
    end
  end

  def test_release_history_keeps_old_paths
    with_repository do |root|
      path = File.join(root, 'CHANGELOG.md')
      File.write(path, '- Added `.agents/bin/test` wrapper (v1.2)')
      commit_fixture(root, 'history')
      apply_upgrade(root)
      assert_equal '- Added `.agents/bin/test` wrapper (v1.2)', File.read(path)
    end
  end

  def test_existing_journal_temporary_file_is_preserved
    with_repository do |root|
      temporary = "#{Shaka::Seam::Upgrader.journal_path(root)}.tmp"
      File.write(temporary, 'leave me')
      _output, error, status = upgrade(root, '--apply', '--digest', report(root).fetch('digest'))
      refute_predicate status, :success?
      assert_includes error, 'Existing upgrade journal temporary file'
      assert_equal 'leave me', File.read(temporary)
    end
  end

  def test_failure_during_destination_creation_restores_sources
    with_repository do |root|
      digest = report(root).fetch('digest')
      assert_raises(Shaka::Error) { failing_creator.new(['--root', root, '--apply', '--digest', digest]).run }
      assert File.file?(File.join(root, '.agents/agent-workflow.yml'))
      refute_path_exists File.join(root, '.agents/shaka/config.yml')
      refute_path_exists Shaka::Seam::Upgrader.journal_path(root)
    end
  end

  def failing_creator
    Class.new(Shaka::Seam::Upgrader) do
      private

      def write_new_state(relative, state)
        @created = (@created || 0) + 1
        raise Errno::EIO, 'injected creation failure' if @created == 2

        super
      end
    end
  end

  def test_set_o_errexit_allows_custom_shell_root_repair
    with_repository do |root|
      write_wrapper(root, 'setup', "#!/bin/sh\nset -o errexit\nroot=$(dirname \"$0\")/../..\nexit 0\n")
      commit_fixture(root, 'errexit')
      assert_equal 'ready', report(root).fetch('status')
    end
  end
end

class SeamUpgradeHistoricalAndIgnoreTest < Minitest::Test
  include SeamUpgradeFixture

  def test_mixed_history_and_current_command_blocks
    with_repository do |root|
      path = File.join(root, 'docs/setup.md')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'Previously we used make; now run .agents/bin/test.')
      commit_fixture(root, 'mixed guidance')
      assert_includes report(root).fetch('blockers').join, 'historical guide old-path reference'
    end
  end

  def test_info_excluded_optional_command_blocks_to_preserve_privacy
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      write_wrapper(root, 'validate-local')
      File.open(File.join(root, '.git/info/exclude'), 'a') { |file| file.write("\n.agents/bin/validate-local\n") }
      assert_includes report(root).fetch('blockers').join, 'overlapping checkout edit'
      assert File.file?(path)
    end
  end
end

class SeamUpgradeDependencySafetyTest < Minitest::Test
  include SeamUpgradeFixture

  def test_make_substitution_and_parent_relative_command_paths_block
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      File.write(path, "run: $(git rev-parse --show-toplevel)/.agents/bin/test\n" \
                       "run: $(CURDIR)/.agents/bin/test\nrun: ../.agents/bin/test\n")
      commit_fixture(root, 'complex prefixes')
      assert_blocked_with(root, 'old-path reference')
    end
  end

  def test_unknown_executable_languages_block
    { 'python' => "ROOT = Path(__file__).resolve().parents[2]\n",
      'node' => "const root = path.join(__dirname, '..', '..')\n" }.each do |language, body|
      with_repository do |root|
        write_wrapper(root, 'setup', "#!/usr/bin/env #{language}\n#{body}")
        commit_fixture(root, 'unknown language')
        assert_blocked_with(root, 'unsupported command language')
      end
    end
  end

  def test_inbound_symlink_to_legacy_command_directory_blocks
    with_repository do |root|
      File.symlink('.agents/bin', File.join(root, 'tools'))
      commit_fixture(root, 'directory link')
      assert_blocked_with(root, 'symlink targets moved path')
    end
  end

  def test_unmoved_tool_calling_moved_sibling_blocks
    with_repository do |root|
      path = File.join(root, '.agents/bin/formatter')
      File.write(path, "#!/bin/sh\nexec \"$(dirname \"$0\")/test\"\n")
      commit_fixture(root, 'unmoved tool')
      assert_blocked_with(root, 'tool uses an invocation-relative path')
    end
  end

  def test_unmoved_tool_using_dot_slash_command_blocks
    with_repository do |root|
      File.write(File.join(root, '.agents/bin/formatter'), "#!/bin/sh\nexec ./test\n")
      commit_fixture(root, 'relative tool')
      assert_blocked_with(root, 'tool uses an invocation-relative path')
    end
  end

  def test_other_ruby_and_shell_relative_paths_block
    ["root = File.join(__dir__, '..', '..')\n", "require_relative 'common'\n",
     ". \"${BASH_SOURCE%/*}/common.sh\"\n", ". \"${0%/*}/common.sh\"\n",
     "load File.join(File.dirname(__FILE__), 'common.rb')\n", "echo \"$0\"\n"].each do |body|
      with_repository do |root|
        write_wrapper(root, 'setup', "#!/bin/sh\n#{body}")
        commit_fixture(root, 'relative dependency')
        assert_blocked_with(root, 'invocation-relative dependency')
      end
    end
  end

  def test_directory_globs_and_codeowners_block
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.github/workflows'))
      File.write(File.join(root, '.github/CODEOWNERS'), '/.agents/bin/ @maintainers')
      File.write(File.join(root, '.github/workflows/ci.yml'), "paths: ['.agents/bin/**']")
      commit_fixture(root, 'directory references')
      preview = report(root)
      assert_equal 'blocked', preview.fetch('status')
      count = preview.fetch('blockers').count { |item| item.include?('old command-directory') }
      assert_equal 2, count
    end
  end

  def test_live_readme_instruction_with_formerly_is_rewritten
    with_repository do |root|
      path = File.join(root, 'README.md')
      File.write(path, 'Run .agents/bin/test (formerly make test).')
      commit_fixture(root, 'live instruction')
      apply_upgrade(root)
      assert_equal 'Run .agents/shaka/bin/test (formerly make test).', File.read(path)
    end
  end

  def test_path_entry_and_backtick_directory_reference_block
    with_repository do |root|
      path = File.join(root, 'README.md')
      File.write(path, "export PATH=\"$PWD/.agents/bin:$PATH\"\nUse `.agents/bin` here.\n")
      commit_fixture(root, 'path entry')
      assert_blocked_with(root, 'old command-directory reference')
    end
  end

  def test_terminal_period_does_not_hide_command_reference
    with_repository do |root|
      path = File.join(root, 'README.md')
      File.write(path, 'Run .agents/bin/test.')
      commit_fixture(root, 'sentence')
      apply_upgrade(root)
      assert_equal 'Run .agents/shaka/bin/test.', File.read(path)
    end
  end
end

class SeamUpgradeAdditionalReferenceTest < Minitest::Test
  include SeamUpgradeFixture

  def test_command_path_with_extension_blocks
    with_repository do |root|
      path = File.join(root, 'README.md')
      File.write(path, 'Run .agents/bin/setup.sh')
      commit_fixture(root, 'command suffix')
      assert_blocked_with(root, 'unsupported old-path spelling')
    end
  end

  def test_backslash_command_path_blocks
    with_repository do |root|
      path = File.join(root, 'README.md')
      File.write(path, 'Run .agents\\bin\\setup')
      commit_fixture(root, 'backslash command')
      assert_blocked_with(root, 'unsupported old-path spelling')
    end
  end

  def test_relative_agent_helper_dependency_blocks
    with_repository do |root|
      path = File.join(root, '.agents/helper')
      File.write(path, "#!/bin/sh\nexec \"$(dirname \"$0\")/bin/test\" \"$@\"\n")
      File.chmod(0o755, path)
      commit_fixture(root, 'relative helper')
      assert_blocked_with(root, 'relative old-command dependency')
    end
  end

  def test_nonexecutable_agent_helper_dependency_blocks
    with_repository do |root|
      path = File.join(root, '.agents/helper.sh')
      File.write(path, "exec \"$(dirname \"$0\")/bin/test\" \"$@\"\n")
      commit_fixture(root, 'interpreter invoked helper')
      assert_blocked_with(root, 'relative old-command dependency')
    end
  end

  def test_relative_helper_with_normalized_separators_blocks
    ['bin//test', 'bin/./test', 'bin/../bin/test'].each do |command|
      with_repository do |root|
        path = File.join(root, '.agents/helper.sh')
        File.write(path, "#!/bin/sh\nexec \"$(dirname \"$0\")/#{command}\"\n")
        commit_fixture(root, 'relative helper path')
        assert_blocked_with(root, 'relative old-command dependency')
      end
    end
  end

  def test_historical_reference_change_invalidates_preview_digest
    with_repository do |root|
      commit_changelog(root, 'Previously .agents/bin/test', 'old history')
      digest = report(root).fetch('digest')
      commit_changelog(root, 'Previously .agents/bin/validate', 'changed history')
      _output, error, status = upgrade(root, '--apply', '--digest', digest)
      refute_predicate status, :success?
      assert_includes error, 'inputs changed'
    end
  end

  def test_joined_directory_and_command_component_blocks
    with_repository do |root|
      path = File.join(root, 'runner.py')
      File.write(path, 'os.path.join(".agents", "bin/test")')
      commit_fixture(root, 'joined command component')
      assert_blocked_with(root, 'segmented old-layout reference')
    end
  end

  def test_executable_without_shebang_blocks_literal_old_command
    with_repository do |root|
      path = File.join(root, 'run-ci')
      File.write(path, "exec .agents/bin/test \"$@\"\n")
      File.chmod(0o755, path)
      commit_fixture(root, 'executable without shebang')
      assert_blocked_with(root, 'executable old-path reference')
    end
  end

  def commit_changelog(root, text, message)
    File.write(File.join(root, 'CHANGELOG.md'), text)
    commit_fixture(root, message)
  end
end

class SeamUpgradeComputedAliasTest < Minitest::Test
  include SeamUpgradeFixture

  def test_computed_workflow_environment_alias_blocks
    with_repository do |root|
      path = File.join(root, '.github/workflows/ci.yml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "env:\n  AGENT_DIR: \u0024{{ github.workspace }}/.agents\n" \
                       "steps:\n  - run: \u0024AGENT_DIR/bin/test\n")
      commit_fixture(root, 'computed workflow directory alias')
      assert_blocked_with(root, 'aliased old-layout directory')
    end
  end
end

class SeamUpgradeCollisionTest < Minitest::Test
  include SeamUpgradeFixture

  def test_real_destination_collision_preserves_other_writer_and_journal
    with_repository do |root|
      digest = report(root).fetch('digest')
      error = assert_raises(Shaka::Error) { colliding_creator.new(['--root', root, '--apply', '--digest', digest]).run }
      assert_includes error.message, 'recovery needed'
      assert_equal 'other writer', File.read(File.join(root, '.agents/shaka/config.yml'))
      assert File.file?(Shaka::Seam::Upgrader.journal_path(root))
    end
  end

  def colliding_creator
    Class.new(Shaka::Seam::Upgrader) do
      private

      def write_new_state(relative, state)
        if relative == '.agents/shaka/config.yml'
          FileUtils.mkdir_p(File.dirname(File.join(@root, relative)))
          File.write(File.join(@root, relative), 'other writer')
        end
        super
      end
    end
  end
end

class SeamUpgradeSymlinkParentTest < Minitest::Test
  include SeamUpgradeFixture

  def test_existing_parent_rejects_symlinked_ancestor
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, 'target/real'))
      File.symlink('target', File.join(root, 'linked'))
      upgrader = Shaka::Seam::Upgrader.new(['--root', root])
      upgrader.instance_variable_set(:@root, root)
      error = assert_raises(Shaka::Error) { upgrader.send(:existing_parent, File.join(root, 'linked/real/file')) }
      assert_includes error.message, 'Unsafe symlink parent'
    end
  end
end

class SeamUpgradeJournalSafetyTest < Minitest::Test
  include SeamUpgradeFixture

  def test_dangling_journal_symlink_is_preserved
    with_repository do |root|
      journal = Shaka::Seam::Upgrader.journal_path(root)
      digest = report(root).fetch('digest')
      File.symlink('missing-journal-target', journal)
      _output, error, status = upgrade(root, '--apply', '--digest', digest)
      refute_predicate status, :success?
      assert_includes error, 'Interrupted upgrade'
      assert File.symlink?(journal)
      assert_equal 'missing-journal-target', File.readlink(journal)
    end
  end

  def test_recovery_rejects_missing_state_without_backtrace
    with_repository do |root|
      journal = Shaka::Seam::Upgrader.journal_path(root)
      File.write(journal, JSON.generate('version' => 1, 'original' => {}))
      _output, error, status = upgrade(root, '--recover')
      refute_predicate status, :success?
      assert_includes error, 'Upgrade journal must contain original and desired states'
      refute_includes error, 'Traceback'
    end
  end

  def test_recovery_rejects_malformed_file_state_without_backtrace
    with_repository do |root|
      journal = write_journal(root, plan_for(root))
      journal.fetch('desired')['.agents/shaka/config.yml'] = { 'type' => 'file', 'data' => 'bad' }
      File.write(Shaka::Seam::Upgrader.journal_path(root), JSON.generate(journal))
      _output, error, status = upgrade(root, '--recover')
      refute_predicate status, :success?
      assert_includes error, 'Invalid upgrade journal state'
      refute_includes error, 'Traceback'
    end
  end

  def test_symlink_target_with_invocation_relative_logic_blocks
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, 'scripts'))
      File.write(File.join(root, 'scripts/validate.sh'), "#!/bin/sh\ncd \"$(dirname \"$0\")/../..\"\n")
      File.chmod(0o755, File.join(root, 'scripts/validate.sh'))
      path = File.join(root, '.agents/bin/validate')
      File.delete(path)
      File.symlink('../../scripts/validate.sh', path)
      commit_fixture(root, 'script link')
      assert_blocked_with(root, 'symlink target has unsupported or invocation-relative behavior')
    end
  end
end

class SeamUpgradePatternSafetyTest < Minitest::Test
  include SeamUpgradeFixture

  def test_contract_directory_glob_blocks
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.github/workflows'))
      File.write(File.join(root, '.github/CODEOWNERS'), '/.agents/*.yml @maintainers')
      File.write(File.join(root, '.github/workflows/ci.yml'), "paths: ['.agents/*.yml']")
      commit_fixture(root, 'contract glob')
      assert_blocked_with(root, 'old layout-directory pattern')
    end
  end

  def test_command_directory_at_sentence_end_blocks
    with_repository do |root|
      File.write(File.join(root, 'README.md'), 'Wrappers live in .agents/bin.')
      commit_fixture(root, 'directory sentence')
      assert_blocked_with(root, 'old command-directory reference')
    end
  end

  # Break: seam init and the layout upgrade drift apart, so an upgraded repository
  # and a freshly initialized one run different wrapper code.
  def test_upgraded_legacy_initializer_wrapper_matches_a_fresh_init
    with_repository do |root, parent|
      %w[setup validate test].each { |name| write_wrapper(root, name, legacy_initializer_wrapper) }
      commit_fixture(root, 'legacy initializer wrappers')
      assert_equal 'applied', apply_upgrade(root).fetch('status')

      initialize_real_fixture(fresh = File.join(parent, 'fresh'))
      assert_equal wrapper_texts(fresh), wrapper_texts(root)
    end
  end

  def wrapper_texts(root)
    %w[setup validate test].to_h { [it, File.read(File.join(root, '.agents/shaka/bin', it))] }
  end

  # The wrapper `seam init` wrote before it adopted the Git root lookup.
  def legacy_initializer_wrapper
    <<~SHELL
      #!/bin/sh
      # Generated by shaka seam init.
      set -eu
      #{ROOT_LINE}
      cd "$root"
      exec bin/probe "$@"
    SHELL
  end

  def initialize_real_fixture(root)
    FileUtils.mkdir_p(File.join(root, 'bin'))
    write_probe(root)
    git!(root, 'init', '-q')
    output, error, status = init_fixture(root)
    assert_predicate status, :success?, "#{error} #{output}"
  end

  def init_fixture(root)
    Open3.capture3(COMMAND, 'seam', 'init', '--root', root, '--setup-command', 'bin/probe',
                   '--test-command', 'bin/probe', '--validate-command', 'bin/probe', '--review-policy', 'none')
  end
end

class SeamUpgradeSnapshotAndLinkTest < Minitest::Test
  include SeamUpgradeFixture

  def test_moved_configuration_old_path_comments_block
    %w[agent-workflow.yml trusted-github-actors.yml].each do |name|
      with_repository do |root|
        path = File.join(root, '.agents', name)
        File.open(path, 'a') { |file| file.write("\n# Run .agents/bin/test\n") }
        commit_fixture(root, 'configuration comment')
        assert_includes report(root).fetch('blockers').join, 'old layout reference in moved configuration'
      end
    end
  end

  def test_edit_between_plan_and_journal_requires_fresh_preview
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      File.write(path, 'run: .agents/bin/test')
      commit_fixture(root, 'ci reference')
      digest = report(root).fetch('digest')
      error = assert_raises(Shaka::Error) { changing_upgrader.new(['--root', root, '--apply', '--digest', digest]).run }
      assert_includes error.message, 'fresh preview'
      assert_equal 'later user edit', File.read(path)
      refute_path_exists Shaka::Seam::Upgrader.journal_path(root)
    end
  end

  def changing_upgrader
    Class.new(Shaka::Seam::Upgrader) do
      private

      def upgrade_journal(plan, report)
        File.write(File.join(@root, 'ci.yml'), 'later user edit')
        super
      end
    end
  end

  def test_edit_after_journal_before_write_is_preserved
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      File.write(path, 'run: .agents/bin/test')
      commit_fixture(root, 'ci reference')
      error = attempt_late_edit(root)
      assert_includes error.message, 'recovery needed'
      assert_equal 'late user edit', File.read(path)
      assert File.file?(Shaka::Seam::Upgrader.journal_path(root))
    end
  end

  def attempt_late_edit(root)
    digest = report(root).fetch('digest')
    assert_raises(Shaka::Error) { late_edit_upgrader.new(['--root', root, '--apply', '--digest', digest]).run }
  end

  def late_edit_upgrader
    Class.new(Shaka::Seam::Upgrader) do
      private

      def write_desired(journal)
        File.write(File.join(@root, 'ci.yml'), 'late user edit')
        super
      end
    end
  end

  def test_symlink_chain_keeps_direct_target
    with_repository do |root|
      directory = File.join(root, '.agents/bin')
      replace_link(directory, 'test', '../../bin/probe')
      replace_link(directory, 'validate', 'test')
      commit_fixture(root, 'command link chain')
      apply_upgrade(root)
      assert_equal 'test', File.readlink(File.join(root, '.agents/shaka/bin/validate'))
      assert_equal '../../../bin/probe', File.readlink(File.join(root, '.agents/shaka/bin/test'))
    end
  end

  def replace_link(directory, name, target)
    path = File.join(directory, name)
    File.delete(path)
    File.symlink(target, path)
  end
end

class SeamUpgradeExecutionSafetyTest < Minitest::Test
  include SeamUpgradeFixture

  def test_moved_command_directory_references_block
    ['export PATH="$root/.agents/bin:$PATH"', 'for f in "$root"/.agents/bin/*; do :; done'].each do |line|
      with_repository do |root|
        source = "#!/bin/sh\n# Generated by shaka seam init.\nset -eu\n#{SeamUpgradeFixture::ROOT_LINE}\n" \
                 "#{line}\nexec \"$root/bin/probe\" \"$@\"\n"
        write_wrapper(root, 'setup', source)
        commit_fixture(root, 'directory-dependent command')
        assert_includes report(root).fetch('blockers').join, 'old command path'
      end
    end
  end

  def test_repaired_shell_and_ruby_wrappers_fail_without_git
    with_repository do |root, parent|
      write_wrapper(root, 'validate', "#!/usr/bin/env ruby\nroot = File.expand_path('../..', __dir__)\n" \
                                      "Dir.chdir(root) { puts 'ran' }\n")
      commit_fixture(root, 'Ruby wrapper')
      apply_upgrade(root)
      Dir.mktmpdir('shaka-no-git') do |empty_path|
        assert_command_fails_without_git(root, parent, empty_path, 'setup', shell: true)
        assert_command_fails_without_git(root, parent, empty_path, 'validate', shell: false)
      end
    end
  end

  def assert_command_fails_without_git(root, parent, empty_path, name, shell:)
    path = File.join(root, '.agents/shaka/bin', name)
    command = shell ? [path] : [RbConfig.ruby, path]
    output, _error, status = Open3.capture3({ 'PATH' => empty_path }, *command, chdir: parent)
    refute_predicate status, :success?
    refute_includes output, 'ran'
  end
end

class SeamUpgradeHostedReviewFixTest < Minitest::Test
  include SeamUpgradeFixture

  def test_inbound_symlink_chain_to_moved_command_blocks
    with_repository do |root|
      command = File.join(root, '.agents/bin/setup')
      File.delete(command)
      File.symlink('../../bin/probe', command)
      File.symlink('.agents/bin/setup', File.join(root, 'setup-alias'))
      commit_fixture(root, 'inbound link chain')
      assert_includes report(root).fetch('blockers').join, 'symlink targets moved path'
    end
  end
end

class SeamUpgradeSymlinkAndReferenceReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_inbound_symlink_with_symlinked_parent_finishes_preview
    with_repository do |root|
      create_symlinked_parent_chain(root)
      commit_fixture(root, 'symlinked parent chain')
      assert_equal 'ready', report(root).fetch('status')
    end
  end

  def create_symlinked_parent_chain(root)
    FileUtils.mkdir_p(File.join(root, 'q/r'))
    FileUtils.mkdir_p(File.join(root, 'q/p'))
    File.write(File.join(root, 'q/p/L'), 'target')
    File.symlink('q/r', File.join(root, 'p'))
    File.symlink('../p/L', File.join(root, 'q/r/L'))
    File.symlink('p/L', File.join(root, 'alias'))
  end

  def test_moved_command_chain_through_unmoved_link_to_moved_command_blocks
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.links'))
      File.symlink('../.agents/bin/validate', File.join(root, '.links/validate'))
      command = File.join(root, '.agents/bin/setup')
      File.delete(command)
      File.symlink('../../.links/validate', command)
      commit_fixture(root, 'moved command link chain')
      assert_includes report(root).fetch('blockers').join, 'unsupported or invocation-relative behavior'
    end
  end

  def test_dotted_variable_prefix_to_old_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.yml'), 'run: $ROOT/./.agents/bin/test')
      commit_fixture(root, 'dotted command reference')
      assert_includes report(root).fetch('blockers').join, 'dynamic old-path reference'
    end
  end
end

class SeamUpgradeRemainingHostedReviewFixTest < Minitest::Test
  include SeamUpgradeFixture

  def test_deleted_indexed_reference_blocks
    with_repository do |root|
      path = File.join(root, '.github/workflows/ci.yml')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'run: .agents/bin/test')
      commit_fixture(root, 'indexed CI reference')
      File.delete(path)
      assert_includes report(root).fetch('blockers').join, 'tracked file is absent'
    end
  end

  def test_undecodable_tracked_reference_blocks
    with_repository do |root|
      path = File.join(root, 'ci.sh')
      File.binwrite(path, "\xFF\nexec .agents/bin/test\n".b)
      commit_fixture(root, 'undecodable CI reference')
      assert_includes report(root).fetch('blockers').join, 'undecodable old-layout reference'
    end
  end

  def test_sparse_omitted_tracked_reference_blocks
    with_repository do |root|
      path = '.github/workflows/ci.yml'
      FileUtils.mkdir_p(File.join(root, '.github/workflows'))
      File.write(File.join(root, path), 'run: .agents/bin/test')
      commit_fixture(root, 'sparse reference')
      git!(root, 'update-index', '--skip-worktree', path)
      File.delete(File.join(root, path))
      assert_includes report(root).fetch('blockers').join, 'tracked file is absent'
    end
  end

  def test_vendored_directory_patterns_are_not_local_blockers
    with_repository do |root|
      path = File.join(root, 'README.md')
      text = "vendor/tool/.agents/bin\nvendor/tool/.agents/*\n"
      File.write(path, text)
      commit_fixture(root, 'vendored paths')
      assert_equal 'ready', report(root).fetch('status')
      apply_upgrade(root)
      assert_equal text, File.read(path)
    end
  end

  def test_symlink_to_python_script_blocks
    with_repository do |root|
      write_python_target(root)
      path = File.join(root, '.agents/bin/setup')
      File.delete(path)
      File.symlink('../../tools/setup.py', path)
      commit_fixture(root, 'Python symlink target')
      assert_includes report(root).fetch('blockers').join, 'unsupported or invocation-relative behavior'
    end
  end

  def write_python_target(root)
    script = File.join(root, 'tools/setup.py')
    FileUtils.mkdir_p(File.dirname(script))
    File.write(script, "#!/usr/bin/env python3\nfrom pathlib import Path\nprint(Path(__file__).parent)\n")
    File.chmod(0o755, script)
  end

  def test_conditional_errexit_still_exits_when_git_fails
    with_repository do |root, parent|
      script = "#!/bin/sh\nif false; then\nset -e\nfi\nroot=$(dirname \"$0\")/../..\n" \
               "cd \"$root\"\nexec \"$root/bin/probe\" \"$@\"\n"
      write_wrapper(root, 'setup', script)
      commit_fixture(root, 'conditional errexit')
      assert_equal 'applied', apply_upgrade(root).fetch('status')
      assert_fake_git_failure(root, parent)
    end
  end

  def assert_fake_git_failure(root, parent)
    Dir.mktmpdir('shaka-failing-git') do |bin|
      fake = File.join(bin, 'git')
      File.write(fake, "#!/bin/sh\nexit 43\n")
      File.chmod(0o755, fake)
      path = File.join(root, '.agents/shaka/bin/setup')
      output, _error, status = Open3.capture3({ 'PATH' => "#{bin}:/usr/bin:/bin" }, path, chdir: parent)
      assert_equal 43, status.exitstatus
      refute_includes output, root
    end
  end

  def test_reference_scan_finds_path_across_chunk_boundary
    with_repository do |root|
      path = File.join(root, 'README.md')
      padding = 'x' * 65_532
      File.write(path, "#{padding}\n.agents/bin/test\n")
      commit_fixture(root, 'boundary reference')
      assert_equal 'ready', report(root).fetch('status')
      apply_upgrade(root)
      assert_includes File.read(path), '.agents/shaka/bin/test'
    end
  end
end

class SeamUpgradeLateReferenceReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_tracked_symlink_to_ignored_script_with_old_command_blocks
    with_repository do |root|
      File.write(File.join(root, '.gitignore'), "private-ci.sh\n")
      File.write(File.join(root, 'private-ci.sh'), "#!/bin/sh\nexec .agents/bin/test\n")
      File.symlink('private-ci.sh', File.join(root, 'ci.sh'))
      commit_fixture(root, 'ignored CI target')
      assert_includes report(root).fetch('blockers').join, 'symlink target contains an old-layout reference'
    end
  end

  def test_tracked_symlink_to_ignored_relative_helper_blocks
    with_repository do |root|
      File.write(File.join(root, '.gitignore'), ".agents/helper\n")
      path = File.join(root, '.agents/helper')
      File.write(path, "#!/bin/sh\nhere=$(dirname \"$(realpath \"$0\")\")\nexec \"$here/bin/test\"\n")
      File.chmod(0o755, path)
      File.symlink('.agents/helper', File.join(root, 'ci-helper'))
      commit_fixture(root, 'ignored relative helper')
      assert_blocked_with(root, 'symlink target contains an old-layout reference')
    end
  end

  def test_parent_traversal_in_old_command_path_blocks
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/cache'))
      File.write(File.join(root, 'ci.yml'), 'run: ./.agents/cache/../bin/test')
      commit_fixture(root, 'parent traversal reference')
      assert_includes report(root).fetch('blockers').join, 'normalized old-layout reference'
    end
  end

  def test_shell_concatenated_old_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nexec \".agents\"/bin/test\n")
      commit_fixture(root, 'shell command pieces')
      assert_includes report(root).fetch('blockers').join, 'segmented old-layout reference'
    end
  end

  def test_repeated_separator_in_old_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.yml'), 'run: ./.agents//bin/test')
      commit_fixture(root, 'repeated separator')
      assert_includes report(root).fetch('blockers').join, 'normalized old-layout reference'
    end
  end
end

class SeamUpgradeFinalReferenceTest < Minitest::Test
  include SeamUpgradeFixture

  def test_segmented_old_layout_path_blocks
    ["File.join(root, '.agents', 'bin', 'test')", "Path('.agents') / 'bin' / 'test'"].each do |source|
      with_repository do |root|
        File.write(File.join(root, 'ci.txt'), source)
        commit_fixture(root, 'segmented reference')
        assert_includes report(root).fetch('blockers').join, 'segmented old-layout reference'
      end
    end
  end

  def test_moved_link_to_ignored_script_with_old_command_blocks
    with_repository do |root|
      write_ignored_target(root)
      command = File.join(root, '.agents/bin/setup')
      File.delete(command)
      File.symlink('../../private/setup.sh', command)
      commit_fixture(root, 'ignored target')
      assert_includes report(root).fetch('blockers').join, 'unsupported or invocation-relative behavior'
    end
  end

  def write_ignored_target(root)
    File.write(File.join(root, '.gitignore'), "private/\n")
    FileUtils.mkdir_p(File.join(root, 'private'))
    target = File.join(root, 'private/setup.sh')
    File.write(target, "#!/bin/sh\nexec .agents/bin/test\n")
    File.chmod(0o755, target)
  end

  def test_internal_dot_segment_in_old_command_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.yml'), 'run: ./.agents/./bin/test')
      commit_fixture(root, 'normalized command')
      assert_includes report(root).fetch('blockers').join, 'normalized old-layout reference'
    end
  end

  def test_unborn_repository_reports_git_inspection_blocker_as_json
    Dir.mktmpdir('shaka-unborn') do |root|
      install_fixture_files(root)
      git!(root, 'init', '-q')
      git!(root, 'add', '-A')
      preview = report(root)
      assert_equal 'blocked', preview.fetch('status')
      assert_includes preview.fetch('blockers').join, 'Cannot inspect checkout edits'
    end
  end

  def test_indexed_old_path_hidden_by_unstaged_edit_blocks
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      File.write(path, 'run: .agents/bin/test')
      commit_fixture(root, 'indexed old path')
      File.write(path, 'run: echo safe')
      assert_includes report(root).fetch('blockers').join, 'indexed old-layout reference differs from worktree'
    end
  end

  def test_blocked_preview_digest_cannot_apply_after_blocker_is_removed
    with_repository do |root|
      path = File.join(root, 'ci.yml')
      blocked = blocked_dynamic_preview(root, path)
      assert_equal 'blocked', blocked.fetch('status')
      remove_and_commit_blocker(root, path)
      assert_equal 'ready', report(root).fetch('status')
      _output, error, status = upgrade(root, '--apply', '--digest', blocked.fetch('digest'))
      refute_predicate status, :success?
      assert_includes error, 'run a fresh preview'
    end
  end

  def blocked_dynamic_preview(root, path)
    File.write(path, 'run: $ROOT/.agents/bin/test')
    commit_fixture(root, 'dynamic old path')
    report(root)
  end

  def remove_and_commit_blocker(root, path)
    File.write(path, 'run: echo safe')
    commit_fixture(root, 'remove blocker')
  end

  def test_dot_relative_directory_references_block
    ['export PATH=./.agents/bin:$PATH', 'find ./.agents/*',
     'export PATH=../.agents/bin:$PATH', 'export PATH=${ROOT}/.agents/bin:$PATH',
     'export PATH="$ROOT/./.agents/bin:$PATH"'].each do |line|
      with_repository do |root|
        File.write(File.join(root, 'ci.yml'), line)
        commit_fixture(root, 'dot-relative directory')
        assert_includes report(root).fetch('blockers').join, 'old'
      end
    end
  end

  def test_historical_guide_line_with_current_instruction_blocks
    with_repository do |root|
      path = File.join(root, 'docs/setup.md')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, 'Previously, validation used Make; use .agents/bin/test for new jobs')
      commit_fixture(root, 'mixed historical guidance')
      assert_includes report(root).fetch('blockers').join, 'historical guide old-path reference'
    end
  end
end

class SeamUpgradeLatestReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_indexed_python_helper_hidden_by_unstaged_edit_blocks
    with_repository do |root|
      path = File.join(root, '.agents/helper.py')
      File.write(path, "from pathlib import Path\ncommand = Path(__file__).parent / 'bin' / 'test'\n")
      commit_fixture(root, 'indexed Python helper')
      File.write(path, "print('safe worktree edit')\n")
      assert_blocked_with(root, 'indexed segmented old-layout reference')
    end
  end

  def test_non_shell_directory_changes_into_old_layout_block
    { 'launcher.py' => "os.chdir('.agents')\nsubprocess.call(['bin/test'])\n",
      'launcher.rb' => "Dir.chdir(root + '/.agents') { system('bin/test') }\n" }.each do |name, source|
      with_repository do |root|
        File.write(File.join(root, name), source)
        commit_fixture(root, 'non-shell old-layout directory')
        assert_blocked_with(root, 'bare old-layout directory')
      end
    end
  end

  def test_computed_change_into_old_layout_directory_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/sh\nroot=$(git rev-parse --show-toplevel)\n" \
                                           "cd \"$root/.agents\"; exec bin/test\n")
      commit_fixture(root, 'computed old-layout directory')
      assert_blocked_with(root, 'bare old-layout directory')
    end
  end

  def test_grouped_directory_changes_into_old_layout_block
    ['(cd .agents && exec bin/test)', 'if cd .agents; then bin/test; fi',
     '(pushd "$root/.agents" && bin/test)'].each do |command|
      with_repository do |root|
        File.write(File.join(root, 'ci.sh'), "#!/bin/bash\n#{command}\n")
        commit_fixture(root, 'grouped old-layout directory')
        assert_blocked_with(root, 'bare old-layout directory')
      end
    end
  end

  def test_normalized_directory_changes_into_old_layout_block
    ['cd .agents/. && exec bin/test', 'cd .agents// && exec bin/test',
     'cd "$root/./.agents/../.agents" && exec bin/test',
     'cd ".age""nts" && exec bin/test'].each do |command|
      with_repository do |root|
        File.write(File.join(root, 'ci.sh'), "#!/bin/sh\n#{command}\n")
        commit_fixture(root, 'normalized old-layout directory')
        assert_blocked_with(root, 'bare old-layout directory')
      end
    end
  end

  def test_python_helper_with_joined_command_components_blocks
    with_repository do |root|
      path = File.join(root, '.agents/helper.py')
      File.write(path, "from pathlib import Path\ncommand = Path(__file__).parent / 'bin' / 'test'\n")
      commit_fixture(root, 'Python relative helper')
      assert_blocked_with(root, 'relative old-command dependency')
    end
  end

  def test_shell_changes_into_bare_old_layout_directory_blocks
    with_repository do |root|
      path = File.join(root, 'ci.sh')
      File.write(path, "#!/bin/sh\ncd .agents\nexec bin/test\n")
      commit_fixture(root, 'bare old-layout directory')
      assert_blocked_with(root, 'bare old-layout directory')
    end
  end

  def test_shell_pushd_into_bare_old_layout_directory_blocks
    with_repository do |root|
      File.write(File.join(root, 'ci.sh'), "#!/bin/bash\npushd .agents\nbin/test\n")
      commit_fixture(root, 'pushd old-layout directory')
      assert_blocked_with(root, 'bare old-layout directory')
    end
  end

  def test_worktree_root_with_trailing_space_is_preserved
    with_spaced_root do |spaced_root, parent|
      assert_equal 'ready', report(spaced_root).fetch('status')
      apply_upgrade(spaced_root)
      output, error, status = Open3.capture3(File.join(spaced_root, '.agents/shaka/bin/setup'), 'arg', chdir: parent)
      assert_empty error
      assert_predicate status, :success?
      assert_equal File.realpath(spaced_root), output.chomp
    end
  end

  def with_spaced_root
    with_repository do |root, parent|
      spaced_root = File.join(parent, 'repo ')
      File.rename(root, spaced_root)
      write_wrapper(spaced_root, 'setup', "#!/usr/bin/env ruby\nroot = File.expand_path('../..', __dir__)\nputs root\n")
      commit_fixture(spaced_root, 'Ruby wrapper in spaced root')
      yield spaced_root, parent
    end
  end
end

class SeamUpgradeCrashReviewTest < Minitest::Test
  include SeamUpgradeFixture

  def test_recovery_removes_owned_journal_hard_link
    with_repository do |root|
      write_journal(root, plan_for(root))
      journal = Shaka::Seam::Upgrader.journal_path(root)
      File.link(journal, "#{journal}.tmp")
      assert_equal 'restored', report(root, '--recover').fetch('status')
      refute_path_exists "#{journal}.tmp"
      assert_equal 'applied', apply_upgrade(root).fetch('status')
    end
  end

  def test_recovery_preserves_unowned_journal_temporary_file
    with_repository do |root|
      write_journal(root, plan_for(root))
      temporary = "#{Shaka::Seam::Upgrader.journal_path(root)}.tmp"
      File.write(temporary, 'unrelated user file')
      assert_equal 'restored', report(root, '--recover').fetch('status')
      assert_equal 'unrelated user file', File.read(temporary)
    end
  end
end

class SeamUpgradeDirectoryReferenceTest < Minitest::Test
  include SeamUpgradeFixture

  def test_legacy_directory_paired_with_moved_command_blocks
    ['env -C .agents bin/test', 'env --chdir=.agents bin/test',
     "subprocess.run(['bin/test'], cwd='.agents')"].each do |source|
      with_repository do |root|
        File.write(File.join(root, 'launcher.sh'), source)
        commit_fixture(root, 'legacy directory and command pair')
        assert_blocked_with(root, 'bare old-layout directory')
      end
    end
  end
end
