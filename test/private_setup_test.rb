# frozen_string_literal: true

require_relative 'private_source_test'
require 'shaka/seam'

module PrivateSetupFixture
  include PrivateSourceFixture

  def with_setup
    with_git_repository do |root|
      commit_project(root)
      FileUtils.mkdir_p(File.join(root, 'bin'))
      File.write(File.join(root, 'bin/probe'), "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, File.join(root, 'bin/probe'))
      commit_file(root, 'bin/probe', 'add probe')
      yield root, head(root)
    end
  end

  def options
    { setup_command: 'bin/probe', validate_command: 'bin/probe', test_command: 'bin/probe',
      review_policy: 'none' }
  end

  def setup_private(root, ref) = Shaka::Seam::PrivateSetup.new(root:, ref:, options: options).setup
  def recovery(root) = Shaka::Seam::PrivateRecovery.new(root:)
  def config_path(root) = File.join(root, '.agents/shaka/config.yml')
  def copy_path(result) = File.join(result.fetch('recovery'), 'current/config.yml')

  def note_private_config(root, note)
    File.open(config_path(root), 'a') { |file| file.puts "# #{note}" }
  end

  def git(root, *)
    system('git', '-C', root, *, exception: true)
  end
end

class PrivateSetupTest < Minitest::Test
  include PrivateSetupFixture

  def test_setup_preserves_exclusion_and_local_authority
    with_setup do |root, ref|
      exclude = File.join(root, '.git/info/exclude')
      File.write(exclude, '# existing')
      result = setup_private(root, ref)
      assert_exclusion_and_copy(root, ref, exclude, result)
    end
  end

  def test_programmatic_options_cannot_grant_private_auto_or_fallback_checks
    with_setup do |root, ref|
      unsafe = options.merge(merge_preference: 'auto', required_checks: ['invented'])
      Shaka::Seam::PrivateSetup.new(root:, ref:, options: unsafe).setup
      config = Shaka::Configuration.private_source(root:, ref:).candidate_config
      assert_equal 'ask', config.merge.fetch('preference')
      refute config.merge.key?('required_checks')
    end
  end

  def test_cli_dispatches_setup_and_inspect
    with_setup do |root, ref|
      output, = capture_io { assert_equal 0, Shaka::Seam.run(cli_setup_args(root, ref)) }
      assert_equal 'complete', JSON.parse(output).fetch('status')
      output, = capture_io { assert_equal 0, Shaka::Seam.run(['private', 'inspect', '--root', root]) }
      assert_equal 'private', JSON.parse(output).fetch('status')
    end
  end

  def cli_setup_args(root, ref)
    ['private', 'setup', '--root', root, '--ref', ref,
     '--setup-command', 'bin/probe', '--validate-command', 'bin/probe',
     '--test-command', 'bin/probe', '--review-policy', 'none']
  end

  def assert_exclusion_and_copy(root, ref, exclude, result)
    assert_equal "# existing\n/.agents/shaka/\n", File.read(exclude)
    assert_equal '', Open3.capture2('git', '-C', root, 'status', '--porcelain').first
    assert_path_exists copy_path(result)
    config = Shaka::Configuration.private_source(root:, ref:).candidate_config
    assert_equal 'ask', config.merge.fetch('preference')
    refute config.merge.key?('required_checks')
  end

  def test_denied_exclusion_leaves_prepared_copy_for_retry
    with_setup do |root, ref|
      error = with_denied_exclusion { assert_raises(Shaka::Error) { setup_private(root, ref) } }
      assert_includes error.message, 'info/exclude'
      refute_path_exists File.join(root, '.agents/shaka')
      assert_path_exists File.join(recovery(root).storage, 'current/config.yml')
      assert_equal 'complete', setup_private(root, ref).fetch('status')
    end
  end

  def with_denied_exclusion
    original = File.method(:open)
    File.define_singleton_method(:open) do |path, *args, **kwargs, &block|
      raise Errno::EACCES, path if path.to_s.end_with?('info/exclude.shaka.lock')

      original.call(path, *args, **kwargs, &block)
    end
    yield
  ensure
    File.define_singleton_method(:open, original)
  end

  def test_interrupted_materialization_resumes
    with_setup do |root, ref|
      setup = Shaka::Seam::PrivateSetup.new(root:, ref:, options: options)
      setup.define_singleton_method(:write_new_file) do |path, content|
        super(path, content)
        raise Errno::EIO, path
      end
      assert_raises(Shaka::Error) { setup.setup }
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
      assert_equal 'complete', setup_private(root, ref).fetch('status')
    end
  end

  def test_non_ascii_command_resumes_after_denied_exclusion
    with_setup do |root, ref|
      selected = options.merge(test_command: 'bin/probe --label=tëst')
      assert_raises(Shaka::Error) do
        with_denied_exclusion { Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected).setup }
      end
      result = Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected).setup
      assert_equal 'complete', result.fetch('status')
    end
  end

  def test_deferred_ci_wrappers_are_a_pair
    with_setup do |root, ref|
      partial = options.merge(validate_local_command: 'bin/probe')
      assert_raises(Shaka::Error) { Shaka::Seam::PrivateSetup.new(root:, ref:, options: partial).setup }
      complete = partial.merge(trigger_hosted_ci_command: 'bin/probe')
      result = Shaka::Seam::PrivateSetup.new(root:, ref:, options: complete).setup
      assert_equal 'complete', result.fetch('status')
      assert_path_exists File.join(root, '.agents/shaka/bin/validate-local')
      assert_path_exists File.join(root, '.agents/shaka/bin/trigger-hosted-ci')
    end
  end
end

class PrivateSetupOptionalTest < Minitest::Test
  include PrivateSetupFixture

  def test_interrupted_second_setup_does_not_inherit_completion_marker
    with_setup do |root, ref|
      selected = options.merge(validate_local_command: 'bin/probe', trigger_hosted_ci_command: 'bin/probe')
      Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected).setup
      git(root, 'clean', '-fdx')
      assert_interrupted_optional_setup(root, ref, selected)
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
    end
  end

  def test_removing_both_optional_wrappers_after_setup_remains_complete
    with_setup do |root, ref|
      selected = options.merge(validate_local_command: 'bin/probe', trigger_hosted_ci_command: 'bin/probe')
      result = Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected).setup
      remove_optional_wrappers(root)
      note_private_config(root, 'edited after removal')
      assert_equal 'private', recovery(root).inspect_checkout.fetch('status')
      assert_includes File.read(copy_path(result)), '# edited after removal'
    end
  end

  def remove_optional_wrappers(root)
    %w[validate-local trigger-hosted-ci].each do |name|
      File.delete(File.join(root, '.agents/shaka/bin', name))
    end
  end

  def test_optional_pair_interruption_remains_partial_and_resumes
    with_setup do |root, ref|
      selected = options.merge(validate_local_command: 'bin/probe', trigger_hosted_ci_command: 'bin/probe')
      assert_interrupted_optional_setup(root, ref, selected)
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
      assert_equal 'complete', Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected).setup.fetch('status')
    end
  end

  def test_deleted_one_optional_wrapper_does_not_replace_complete_copy
    with_setup do |root, ref|
      selected = options.merge(validate_local_command: 'bin/probe', trigger_hosted_ci_command: 'bin/probe')
      result = Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected).setup
      File.delete(File.join(root, '.agents/shaka/bin/validate-local'))
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
      assert_path_exists File.join(result.fetch('recovery'), 'current/bin/validate-local')
    end
  end

  def test_nonexecutable_required_wrapper_does_not_replace_complete_copy
    with_setup do |root, ref|
      result = setup_private(root, ref)
      wrapper = File.join(root, '.agents/shaka/bin/test')
      File.chmod(0o644, wrapper)
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
      assert File.executable?(File.join(result.fetch('recovery'), 'current/bin/test'))
    end
  end

  def test_malformed_contract_does_not_replace_complete_copy
    with_setup do |root, ref|
      result = setup_private(root, ref)
      File.write(config_path(root), 'invalid: [')
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
      assert_includes File.read(copy_path(result)), 'preference: ask'
    end
  end

  def test_uncommitted_external_review_prompt_does_not_replace_complete_copy
    with_setup do |root, ref|
      result = setup_private(root, ref)
      add_uncommitted_external_prompt(root)
      assert_equal 'partial', Shaka::Configuration.private_source(root:, ref:).status
      assert_equal 'partial', recovery(root).inspect_checkout.fetch('status')
      refute_includes File.read(copy_path(result)), 'docs/review.md'
    end
  end

  def add_uncommitted_external_prompt(root)
    FileUtils.mkdir_p(File.join(root, 'docs'))
    File.write(File.join(root, 'docs/review.md'), 'local prompt')
    policy = YAML.safe_load_file(config_path(root))
    policy['review'] = review_policy('prompt_file' => 'docs/review.md')
    File.write(config_path(root), YAML.dump(policy))
  end

  def assert_interrupted_optional_setup(root, ref, selected)
    setup = Shaka::Seam::PrivateSetup.new(root:, ref:, options: selected)
    setup.define_singleton_method(:write_new_file) do |path, content|
      raise Errno::EIO, path if path.end_with?('trigger-hosted-ci')

      super(path, content)
    end
    assert_raises(Shaka::Error) { setup.setup }
  end
end

class PrivateIdentityTest < Minitest::Test
  include PrivateSetupFixture

  def test_concurrent_identity_assignment_uses_one_complete_marker
    with_setup do |root, _ref|
      locations = Array.new(2) { Thread.new { recovery(root).storage } }.map(&:value)
      assert_equal locations.first, locations.last
      assert_match(/\A[0-9a-f]{64}\z/, File.read(File.join(root, '.git/shaka-private-id')))
    end
  end

  def test_stale_pending_identity_does_not_block_assignment
    with_setup do |root, _ref|
      File.write(File.join(root, '.git/shaka-private-id-pending-stale'), '')
      assert_match(/\A[0-9a-f]{64}\z/, File.basename(recovery(root).storage))
    end
  end
end

class PrivateGitEnvironmentTest < Minitest::Test
  include PrivateSetupFixture

  def test_exported_repository_variables_cannot_redirect_recovery_or_preflight
    with_setup do |root, ref|
      other = "#{root}-git-environment"
      FileUtils.mkdir_p(other)
      git(other, 'init', '--quiet')
      with_foreign_git_environment(root, other) do
        assert_recovery_stays_in_root(root, ref, other)
      end
    ensure
      FileUtils.rm_rf(other) if other
    end
  end

  def assert_recovery_stays_in_root(root, ref, other)
    result = setup_private(root, ref)
    assert result.fetch('recovery').start_with?(File.join(File.realpath(root), '.git/'))
    assert_equal 'complete', Shaka::Configuration.private_source(root:, ref:).status
    refute_path_exists File.join(other, '.git/shaka')
  end

  def test_exported_repository_variables_do_not_hide_trusted_adoption
    with_setup do |root, old_ref|
      trusted = future_trusted_seam(root, old_ref)
      other = "#{root}-foreign-git"
      FileUtils.mkdir_p(other)
      git(other, 'init', '--quiet')
      with_foreign_git_environment(root, other) { assert_trusted_setup_refused(root, trusted) }
    ensure
      FileUtils.rm_rf(other) if other
    end
  end

  def future_trusted_seam(root, old_ref)
    write_private_seam(root)
    git(root, 'add', '.agents/shaka')
    git(root, 'commit', '-qm', 'trusted adoption')
    trusted = head(root)
    git(root, 'checkout', '-q', old_ref)
    trusted
  end

  def assert_trusted_setup_refused(root, trusted)
    assert_equal 'present', Shaka::Configuration.private_source(root:, ref: trusted).trusted_source
    assert_raises(Shaka::Error) { setup_private(root, trusted) }
    refute_path_exists File.join(root, '.git/shaka-private-id')
  end

  def with_foreign_git_environment(root, other)
    original = %w[GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE].to_h { |name| [name, ENV.fetch(name, nil)] }
    ENV['GIT_DIR'] = File.join(other, '.git')
    ENV['GIT_COMMON_DIR'] = File.join(other, '.git')
    ENV['GIT_WORK_TREE'] = root
    ENV['GIT_INDEX_FILE'] = File.join(other, '.git/index')
    yield
  ensure
    original&.each { |name, value| ENV[name] = value }
  end
end

class PrivateSetupRefusalTest < Minitest::Test
  include PrivateSetupFixture

  def test_trusted_configuration_refusal_creates_no_identity
    with_setup do |root, _ref|
      write_private_seam(root)
      git(root, 'add', '.agents/shaka')
      git(root, 'commit', '-qm', 'team setup')
      assert_raises(Shaka::Error) { setup_private(root, head(root)) }
      refute_path_exists File.join(root, '.git/shaka-private-id')
    end
  end

  def test_staged_adoption_refusal_creates_no_identity
    with_setup do |root, ref|
      FileUtils.mkdir_p(File.join(root, '.agents/shaka'))
      File.write(config_path(root), "team: true\n")
      git(root, 'add', '.agents/shaka/config.yml')
      assert_raises(Shaka::Error) { setup_private(root, ref) }
      refute_path_exists File.join(root, '.git/shaka-private-id')
    end
  end

  def test_existing_crlf_exclusion_is_not_duplicated
    with_setup do |root, ref|
      exclude = File.join(root, '.git/info/exclude')
      File.write(exclude, "# existing\r\n/.agents/shaka/\r\n")
      setup_private(root, ref)
      assert_equal 1, File.read(exclude).scan('/.agents/shaka/').length
    end
  end

  def test_untracked_legacy_contract_refuses_before_private_writes
    with_setup do |root, ref|
      FileUtils.mkdir_p(File.join(root, '.agents'))
      File.write(File.join(root, '.agents/agent-workflow.yml'), "version: 1\n")
      assert_raises(Shaka::Error) { setup_private(root, ref) }
      refute_path_exists File.join(root, '.agents/shaka')
      refute_path_exists File.join(root, '.git/shaka-private-id')
      refute_includes File.read(File.join(root, '.git/info/exclude')), '/.agents/shaka/'
    end
  end

  def test_later_exclusion_negation_blocks_setup_without_duplicate_rule
    with_setup do |root, ref|
      exclude = File.join(root, '.git/info/exclude')
      rules = "/.agents/shaka/\n!/.agents/shaka/\n"
      File.write(exclude, rules)
      2.times { assert_raises(Shaka::Error) { setup_private(root, ref) } }
      assert_equal rules, File.read(exclude)
      refute_path_exists File.join(root, '.agents/shaka')
    end
  end

  def test_higher_priority_negation_does_not_grow_exclusion_on_retry
    with_setup do |root, ref|
      exclude = File.join(root, '.git/info/exclude')
      File.write(File.join(root, '.gitignore'), "!/.agents/shaka/\n")
      2.times { assert_raises(Shaka::Error) { setup_private(root, ref) } }
      assert_equal 1, File.read(exclude).scan('/.agents/shaka/').length
      refute_path_exists File.join(root, '.agents/shaka')
    end
  end
end

class PrivateCommandTest < Minitest::Test
  include PrivateSetupFixture

  def test_cli_rejects_missing_setup_ref_and_restore_destination
    with_setup do |root, _ref|
      [['setup', '--root', root], ['restore', '--root', root], ['unknown', '--root', root]].each do |args|
        _stdout, stderr = capture_io { assert_equal 1, Shaka::Seam.run(['private', *args]) }
        refute_empty stderr
      end
    end
  end

  def test_cli_rejects_flags_for_other_operations
    with_setup do |root, ref|
      _stdout, stderr = capture_io do
        assert_equal 1, Shaka::Seam.run(['private', 'list', '--root', root, '--ref', ref])
      end
      assert_includes stderr, '--ref'
    end
  end

  def test_failed_restore_creates_no_identity_or_unknown_storage
    with_setup do |root, _ref|
      inspection = "#{root}-missing-recovery"
      marker = File.join(root, '.git/shaka-private-id')
      unknown = 'a' * 64
      assert_cli_restore_missing(root, inspection)
      assert_raises(Shaka::Error) { recovery_without_identity(root).restore(to: inspection, id: unknown) }
      refute_path_exists marker
      refute_path_exists File.join(root, '.git/shaka/private-worktrees', unknown)
      refute_path_exists inspection
    end
  end

  def assert_cli_restore_missing(root, inspection)
    _output, error = capture_io do
      assert_equal 1, Shaka::Seam.run(['private', 'restore', '--root', root, '--to', inspection])
    end
    assert_includes error, 'No recovery copy'
  end

  def recovery_without_identity(root) = Shaka::Seam::PrivateRecovery.new(root:, assign_identity: false)
end

class PrivateSetupFailureTest < Minitest::Test
  include PrivateSetupFixture

  def test_denied_recovery_write_reports_its_path
    with_setup do |root, ref|
      destination = recovery(root).storage
      with_denied_storage(destination) do
        error = assert_raises(Shaka::Error) { setup_private(root, ref) }
        assert_includes error.message, destination
      end
    end
  end

  def with_denied_storage(destination)
    original = FileUtils.method(:mkdir_p)
    FileUtils.define_singleton_method(:mkdir_p) do |path, **args|
      raise Errno::EACCES, path if path == destination

      original.call(path, **args)
    end
    yield
  ensure
    FileUtils.define_singleton_method(:mkdir_p, original)
  end
end

class PrivateRecoveryTest < Minitest::Test
  include PrivateSetupFixture

  def test_list_and_restore_by_id_do_not_assign_identity
    with_setup do |root, ref|
      result = setup_private(root, ref)
      linked = "#{root}-read-only"
      git(root, 'worktree', 'add', '--quiet', '-b', 'read-only', linked)
      inspection = "#{root}-read-only-inspection"
      assert_read_only_commands(root, linked, result, inspection)
    ensure
      git(root, 'worktree', 'remove', '--force', linked) if linked && File.exist?(linked)
      FileUtils.rm_rf(inspection) if inspection
    end
  end

  def assert_read_only_commands(root, linked, result, inspection)
    marker = File.join(root, '.git/worktrees/read-only/shaka-private-id')
    output, = capture_io { assert_equal 0, Shaka::Seam.run(['private', 'list', '--root', linked]) }
    assert_equal 1, JSON.parse(output).length
    refute_path_exists marker
    id = File.basename(result.fetch('recovery'))
    capture_io { assert_equal 0, Shaka::Seam.run(['private', 'restore', '--root', linked, '--id', id, '--to', inspection]) }
    refute_path_exists marker
  end

  def test_linked_worktrees_keep_distinct_copies_after_deletion
    with_setup do |root, ref|
      linked = "#{root}-linked"
      first, second = setup_linked_copies(root, ref, linked)
      assert_linked_isolation(root, first, second)
      assert_sibling_restore_refused(root, linked, second)
      assert_deleted_recovery(root, linked, second)
      assert_recreated_worktree_is_new(root, ref, linked, second)
    ensure
      git(root, 'worktree', 'remove', '--force', linked) if File.exist?(linked)
    end
  end

  def assert_recreated_worktree_is_new(root, ref, linked, old)
    git(root, 'worktree', 'add', '--quiet', '-b', 'linked-again', linked)
    fresh = setup_private(linked, ref)
    refute_equal old.fetch('recovery'), fresh.fetch('recovery')
    assert_path_exists File.join(old.fetch('recovery'), 'current/local-note')
    assert_equal 3, recovery(root).list.length
  end

  def assert_deleted_recovery(root, linked, result)
    git(root, 'worktree', 'remove', '--force', linked)
    assert_deleted_worktree_restore(root, result)
    File.delete(File.join(result.fetch('recovery'), 'manifest.json'))
    assert_equal 2, recovery(root).list.length
  end

  def assert_sibling_restore_refused(root, linked, result)
    git(linked, 'clean', '-fdx')
    id = File.basename(result.fetch('recovery'))
    assert_raises(Shaka::Error) { recovery(root).restore(id:, to: File.join(linked, '.agents/shaka')) }
  end

  def assert_deleted_worktree_restore(root, result)
    id = File.basename(result.fetch('recovery'))
    inspection = "#{root}-deleted-inspection"
    recovery(root).restore(id:, to: inspection)
    assert_equal 'linked only', File.read(File.join(inspection, 'local-note'))
  ensure
    FileUtils.rm_rf(inspection) if inspection
  end

  def setup_linked_copies(root, ref, linked)
    git(root, 'worktree', 'add', '--quiet', '-b', 'linked', linked)
    first = setup_private(root, ref)
    second = setup_private(linked, ref)
    File.write(File.join(linked, '.agents/shaka/local-note'), 'linked only')
    recovery(linked).inspect_checkout
    [first, second]
  end

  def assert_linked_isolation(root, first, second)
    refute_equal first.fetch('recovery'), second.fetch('recovery')
    refute_path_exists File.join(first.fetch('recovery'), 'current/local-note')
    assert_equal 'linked only', File.read(File.join(second.fetch('recovery'), 'current/local-note'))
    assert_equal 1, File.read(File.join(root, '.git/info/exclude')).scan('/.agents/shaka/').length
  end
end

class PrivateRecoveryInterruptedTest < Minitest::Test
  include PrivateSetupFixture

  def test_setup_refuses_when_only_previous_copy_survives_clean
    with_setup do |root, ref|
      result = setup_private(root, ref)
      storage = result.fetch('recovery')
      FileUtils.mv(File.join(storage, 'current'), File.join(storage, 'previous'))
      git(root, 'clean', '-fdx')
      assert_raises(Shaka::Error) { setup_private(root, ref) }
      assert_includes File.read(File.join(storage, 'previous/config.yml')), 'preference: ask'
    end
  end

  def test_restore_defaults_to_previous_when_current_is_missing
    with_setup do |root, ref|
      result = setup_private(root, ref)
      storage = result.fetch('recovery')
      inspection = "#{root}-previous-fallback"
      restored = restore_after_missing_current(root, storage, inspection)
      assert_equal File.join(storage, 'previous'), restored.fetch('source')
      assert_includes File.read(File.join(inspection, 'config.yml')), 'preference: ask'
    ensure
      FileUtils.rm_rf(inspection) if inspection
    end
  end

  def restore_after_missing_current(root, storage, inspection)
    FileUtils.mv(File.join(storage, 'current'), File.join(storage, 'previous'))
    recovery(root).restore(to: inspection)
  end

  def test_missing_current_keeps_previous_during_refresh
    with_setup do |root, ref|
      result = setup_private(root, ref)
      storage = result.fetch('recovery')
      FileUtils.mv(File.join(storage, 'current'), File.join(storage, 'previous'))
      note_private_config(root, 'new edit')
      recovery(root).inspect_checkout
      assert_includes File.read(File.join(storage, 'previous/config.yml')), 'preference: ask'
      assert_includes File.read(copy_path(result)), '# new edit'
    end
  end
end

class PrivateRecoveryConcurrencyTest < Minitest::Test
  include PrivateSetupFixture

  def test_two_inspections_keep_the_pre_edit_copy
    with_setup do |root, ref|
      result = setup_private(root, ref)
      note_private_config(root, 'edited once')
      run_concurrent_inspections(root)
      assert_includes File.read(File.join(result.fetch('recovery'), 'previous/config.yml')), 'preference: ask'
      assert_includes File.read(copy_path(result)), '# edited once'
    end
  end

  def run_concurrent_inspections(root)
    first, started, release = paused_recovery(root)
    a = Thread.new { first.inspect_checkout }
    started.pop
    b = Thread.new { recovery(root).inspect_checkout }
    release << true
    a.value
    b.value
  end

  def test_restore_waits_for_copy_rotation
    with_setup do |root, ref|
      setup_private(root, ref)
      note_private_config(root, 'rotated')
      assert_restore_waits_for_rotation(root)
    end
  end

  def assert_restore_waits_for_rotation(root)
    started = Queue.new
    release = Queue.new
    rotating = paused_manifest_recovery(root, started, release)
    worker = Thread.new { rotating.inspect_checkout }
    started.pop
    assert_locked_restore(root, release, worker)
  ensure
    release << true if release && worker&.alive?
    worker&.join
  end

  def paused_manifest_recovery(root, started, release)
    rotating = recovery(root)
    rotating.define_singleton_method(:write_manifest) do |inventory|
      started << true
      release.pop
      super(inventory)
    end
    rotating
  end

  def assert_locked_restore(root, release, worker)
    inspection = "#{root}-rotation-inspection"
    reader = Thread.new { recovery(root).restore(to: inspection) }
    refute reader.join(0.05), 'restore should wait for the storage lock'
    release << true
    worker.value
    assert_includes File.read(File.join(reader.value.fetch('path'), 'config.yml')), '# rotated'
  ensure
    release << true if worker&.alive?
    reader&.join
    FileUtils.rm_rf(inspection) if inspection
  end

  def paused_recovery(root)
    started = Queue.new
    release = Queue.new
    first = recovery(root)
    first.define_singleton_method(:save_from) do |tree|
      started << true
      release.pop
      super(tree)
    end
    [first, started, release]
  end
end

class PrivateRecoveryTargetTest < Minitest::Test
  include PrivateSetupFixture

  def test_restore_refuses_another_clones_worktree
    with_setup do |root, ref|
      setup_private(root, ref)
      other = "#{root}-other-clone"
      FileUtils.mkdir_p(other)
      git(other, 'init', '--quiet')
      assert_raises(Shaka::Error) { recovery(root).restore(to: File.join(other, '.agents/shaka')) }
    ensure
      FileUtils.rm_rf(other) if other
    end
  end
end

class PrivateRecoveryRestoreTest < Minitest::Test
  include PrivateSetupFixture

  def test_manifest_failure_rolls_back_rotation
    with_setup do |root, ref|
      result = setup_private(root, ref)
      note_private_config(root, 'first edit')
      recovery(root).inspect_checkout
      assert_manifest_failure_preserves_copies(root, result)
    end
  end

  def assert_manifest_failure_preserves_copies(root, result)
    note_private_config(root, 'second edit')
    reader = recovery(root)
    reader.define_singleton_method(:write_manifest) { |_inventory| raise Shaka::Error, 'manifest failed' }
    assert_raises(Shaka::Error) { reader.inspect_checkout }
    assert_includes File.read(copy_path(result)), '# first edit'
    assert_includes File.read(File.join(result.fetch('recovery'), 'previous/config.yml')), 'preference: ask'
  end

  def test_failed_rotation_preserves_current_and_previous
    with_setup do |root, ref|
      result = setup_private(root, ref)
      note_private_config(root, 'first edit')
      recovery(root).inspect_checkout
      assert_failed_rotation_preserves_copies(root, result)
    end
  end

  def assert_failed_rotation_preserves_copies(root, result)
    previous = File.join(result.fetch('recovery'), 'previous/config.yml')
    prior = File.read(previous)
    note_private_config(root, 'second edit')
    with_denied_rotation(result.fetch('recovery')) do
      assert_raises(Errno::EACCES) { recovery(root).inspect_checkout }
    end
    assert_includes File.read(copy_path(result)), '# first edit'
    assert_equal prior, File.read(previous)
  end

  def with_denied_rotation(storage)
    original = File.method(:rename)
    File.define_singleton_method(:rename) do |from, to|
      raise Errno::EACCES, from if from == File.join(storage, 'current') && to == File.join(storage, 'previous')

      original.call(from, to)
    end
    yield
  ensure
    File.define_singleton_method(:rename, original)
  end

  def test_git_clean_keeps_copy_and_adoption_restore_only_compares
    with_setup do |root, ref|
      result = setup_private(root, ref)
      config = config_path(root)
      change_private_preference(root)
      assert_previous_copy(root, result)
      assert_clean_preserves_edited_copy(root, ref, result, config)
      assert_comparison_restore(root, result)
    end
  end

  def assert_clean_preserves_edited_copy(root, ref, result, config)
    git(root, 'clean', '-fdx')
    refute_path_exists config
    assert_raises(Shaka::Error) { setup_private(root, ref) }
    assert_includes File.read(copy_path(result)), 'preference: auto'
  end

  def change_private_preference(root)
    config = config_path(root)
    File.write(config, File.read(config).sub('preference: ask', 'preference: auto'))
    recovery(root).inspect_checkout
  end

  def assert_previous_copy(root, result)
    previous = File.join(result.fetch('recovery'), 'previous/config.yml')
    assert_includes File.read(previous), 'preference: ask'
    inspection = "#{root}-previous-inspection"
    recovery(root).restore(to: inspection, previous: true)
    assert_equal File.read(previous), File.read(File.join(inspection, 'config.yml'))
  ensure
    FileUtils.rm_rf(inspection) if inspection
  end

  def assert_comparison_restore(root, result)
    stage_team_adoption(root)
    assert_equal 'adopted', recovery(root).inspect_checkout.fetch('status')
    inspection = "#{root}-inspection"
    recovery(root).restore(to: inspection)
    assert_restored_copy(root, result, inspection)
  ensure
    FileUtils.rm_rf(inspection) if inspection
  end

  def assert_restored_copy(root, result, inspection)
    assert_equal File.read(copy_path(result)), File.read(File.join(inspection, 'config.yml'))
    assert_equal "team: true\n", File.read(config_path(root))
    assert_raises(Shaka::Error) { recovery(root).restore(to: File.join(root, '.agents/shaka')) }
  end

  def stage_team_adoption(root)
    config = config_path(root)
    FileUtils.mkdir_p(File.dirname(config))
    File.write(config, "team: true\n")
    git(root, 'add', '-f', '.agents/shaka/config.yml')
  end
end

class PrivateAdoptionTest < Minitest::Test
  include PrivateSetupFixture

  def test_outside_merge_overwrites_ignored_file_but_keeps_copy
    with_setup do |root, ref|
      result = setup_private(root, ref)
      note_private_config(root, 'personal: before pull')
      recovery(root).inspect_checkout
      adopt_from_team_branch(root)
      assert_adoption_preserves_copy(root, result)
    end
  end

  def test_staged_partial_adoption_does_not_refresh_private_copy
    with_setup do |root, ref|
      result = setup_private(root, ref)
      git(root, 'add', '-f', '.agents/shaka/bin/setup')
      File.write(config_path(root), "edited after adoption\n")
      report = recovery(root).inspect_checkout
      assert_equal 'adopted', report.fetch('status')
      assert_includes report.fetch('adoption_paths'), '.agents/shaka/bin/setup'
      refute_includes File.read(copy_path(result)), 'edited after adoption'
    end
  end

  def test_adoption_refuses_symlinked_agents_ancestor_before_comparison
    with_setup do |root, ref|
      setup_private(root, ref)
      external = replace_agents_with_external_link(root)
      assert_raises(Shaka::Error) { recovery(root).inspect_checkout }
    ensure
      FileUtils.rm_rf(external) if external
    end
  end

  def replace_agents_with_external_link(root)
    File.write(File.join(root, '.agents/agent-workflow.yml'), "version: 1\n")
    git(root, 'add', '.agents/agent-workflow.yml')
    FileUtils.rm_rf(File.join(root, '.agents'))
    external = "#{root}-external-agents"
    FileUtils.mkdir_p(File.join(external, 'shaka'))
    File.write(File.join(external, 'shaka/config.yml'), 'outside')
    File.symlink(external, File.join(root, '.agents'))
    external
  end

  def assert_adoption_preserves_copy(root, result)
    assert_equal "team: after pull\n", File.read(config_path(root))
    report = recovery(root).inspect_checkout
    assert_equal 'adopted', report.fetch('status')
    assert_includes report.fetch('changed'), 'config.yml'
    assert_includes report.fetch('hidden_untracked'), '.agents/shaka/bin/setup'
    assert_includes File.read(copy_path(result)), '# personal: before pull'
  end

  def adopt_from_team_branch(root)
    branch = Open3.capture2('git', '-C', root, 'branch', '--show-current').first.strip
    git(root, 'checkout', '-q', '-b', 'team')
    File.write(config_path(root), "team: after pull\n")
    git(root, 'add', '-f', '.agents/shaka/config.yml')
    git(root, 'commit', '-qm', 'team adopts Shaka')
    git(root, 'checkout', '-q', branch)
    note_private_config(root, 'personal: before pull')
    git(root, 'merge', '--ff-only', 'team')
  end
end
