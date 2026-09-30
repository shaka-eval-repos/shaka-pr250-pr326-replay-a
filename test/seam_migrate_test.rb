# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'yaml'

module SeamMigrateHelpers
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  FIXTURES = File.expand_path('fixtures/seam_migrate', __dir__)

  private

  def migrate(root, sha, *flags)
    Open3.capture3(COMMAND, 'seam', 'migrate', '--root', root, '--from-ref', sha, *flags)
  end

  def migrate_report(root, sha, *flags)
    output, error, status = migrate(root, sha, *flags)
    assert_predicate status, :success?, error
    JSON.parse(output)
  end

  def with_legacy_repository(fixture)
    Dir.mktmpdir('shaka-seam-migrate') do |root|
      install_wrappers(root)
      File.write(File.join(root, '.agents/agent-workflow.yml'), File.read(File.join(FIXTURES, fixture)))
      sha = commit_repository(root)
      yield root, sha, snapshot(root)
    end
  end

  def install_wrappers(root)
    FileUtils.mkdir_p(File.join(root, '.agents/bin'))
    %w[setup validate test].each do |name|
      path = File.join(root, '.agents/bin', name)
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
  end

  def rewrite_yaml(root)
    path = File.join(root, '.agents/agent-workflow.yml')
    data = YAML.safe_load_file(path)
    File.write(path, YAML.dump(yield(data)))
    commit_repository(root)
  end

  def snapshot(root)
    paths = Dir.glob(File.join(root, '**/*'), File::FNM_DOTMATCH)
    paths.reject { |path| File.directory?(path) || path.include?('/.git/') }.to_h do |path|
      [path, [File.read(path), File.stat(path).mode & 0o777]]
    end
  end

  def commit_repository(root)
    git!(root, 'init') unless File.directory?(File.join(root, '.git'))
    git!(root, 'add', '.')
    git!(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', 'trusted')
    sha, status = Open3.capture2('git', '-C', root, 'rev-parse', 'HEAD')
    raise 'rev-parse failed' unless status.success?

    sha.strip
  end

  def git!(root, *)
    output, status = Open3.capture2e('git', '-C', root, *)
    raise output unless status.success?
  end
end

class SeamMigrateHelpTest < Minitest::Test
  include SeamMigrateHelpers

  def test_help_lists_migrate
    output, error, status = Open3.capture3(COMMAND, 'seam', 'check', '--help')

    assert_predicate status, :success?, error
    assert_includes output, 'shaka seam migrate'
  end

  def test_plan_and_apply_cannot_be_combined
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      _output, error, status = migrate(root, sha, '--plan', '--apply')

      refute_predicate status, :success?
      assert_includes error, '--apply'
    end
  end
end

class SeamMigratePlanTest < Minitest::Test
  include SeamMigrateHelpers

  def test_plan_is_the_default_and_writes_nothing
    with_legacy_repository('react_on_rails_shape.yml') do |root, sha, before|
      report = migrate_report(root, sha)
      validation = report.fetch('validation')

      assert_equal 'plan', report.fetch('mode')
      assert_equal before, snapshot(root)
      refute_empty validation.fetch('previous_trusted_ref')
      refute_empty validation.fetch('candidate_local')
      refute_equal validation.fetch('previous_trusted_ref'), validation.fetch('candidate_local')
    end
  end

  def test_react_on_rails_shape_classifies_fields_without_inferring_review_or_merge
    with_legacy_repository('react_on_rails_shape.yml') do |root, sha|
      report = migrate_report(root, sha)

      assert_ror_classification(report)
      refute report.fetch('established').key?('review')
      refute report.fetch('established').key?('merge')
    end
  end

  def test_control_plane_flow_shape_retires_github_facts_and_keeps_typed_policy
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      report = migrate_report(root, sha)

      assert_cpf_classification(report)
      assert_equal 'none', report.dig('established', 'review', 'required')
      assert_equal 'ask', report.dig('established', 'merge', 'preference')
    end
  end

  def test_seam_required_checks_are_retained
    with_legacy_repository('control_plane_flow_shape.yml') do |root|
      sha = rewrite_yaml(root) { |data| data.merge('merge' => data['merge'].merge('required_checks' => ['checks'])) }
      report = migrate_report(root, sha)

      assert_includes report.fetch('retained'), 'merge.required_checks'
      assert_equal ['checks'], report.dig('established', 'merge', 'required_checks')
    end
  end

  def test_plan_blocks_invalid_seam_required_checks
    with_legacy_repository('control_plane_flow_shape.yml') do |root|
      sha = rewrite_yaml(root) { |data| data.merge('merge' => data['merge'].merge('required_checks' => [])) }

      assert_includes migrate_report(root, sha).fetch('blocking'), 'merge.required_checks must not be empty'
    end
  end

  def test_command_role_collision_chooses_the_stricter_temporary_behavior
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('commands' => swapped_commands) }
      collision = migrate_report(root, sha).fetch('command_collisions').find { |item| item.fetch('role') == 'test' }

      refute_nil collision
      assert_includes collision.fetch('temporary_behavior'), 'stricter'
      assert_includes collision.fetch('temporary_behavior'), '.agents/bin/validate'
    end
  end

  private

  def assert_ror_classification(report)
    assert_includes report.fetch('retained'), 'base_branch'
    assert_includes report.fetch('moved_to_agents'), 'review_gate'
    assert_includes report.fetch('moved_to_operational_config'), 'hosted_ci_trigger'
    assert_includes report.fetch('retired'), 'coordination_backend'
    assert_includes report.fetch('blocking'), 'review.required'
    assert_includes report.fetch('blocking'), 'merge.preference'
  end

  def assert_cpf_classification(report)
    assert_includes report.fetch('retained'), 'review.required'
    assert_includes report.fetch('retired'), 'commands'
    assert_includes report.fetch('retired'), 'protection'
    assert_includes report.fetch('retired'), 'merge.method'
    assert_includes report.fetch('moved_to_operational_config'), 'trusted_actions'
    assert_empty report.fetch('blocking')
  end

  def swapped_commands
    { 'setup' => '.agents/bin/setup', 'validate' => '.agents/bin/test', 'test' => '.agents/bin/validate' }
  end
end

class SeamMigrateApplyTest < Minitest::Test
  include SeamMigrateHelpers

  def test_unknown_keys_block_rather_than_guess
    with_legacy_repository('react_on_rails_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('mystery_policy' => 'do-not-guess') }

      assert_includes migrate_report(root, sha).fetch('blocking'), 'mystery_policy'
      _output, error, status = migrate(root, sha, '--apply', '--review-policy', 'none', '--merge-preference', 'ask')
      refute_predicate status, :success?
      assert_includes error, 'mystery_policy'
    end
  end

  def test_apply_refuses_when_review_or_merge_cannot_be_established
    with_legacy_repository('react_on_rails_shape.yml') do |root, sha, before|
      _output, error, status = migrate(root, sha, '--apply')

      refute_predicate status, :success?
      assert_includes error, 'review.required'
      assert_equal before, snapshot(root)
    end
  end

  def test_apply_is_atomic_when_a_destination_already_exists
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      yaml = File.read(File.join(root, '.agents/agent-workflow.yml'))
      File.write(File.join(root, '.agents/shaka.md'), "repository owned pointer\n")
      _output, error, status = migrate(root, sha, '--apply')

      refute_predicate status, :success?
      assert_includes error, '.agents/shaka.md'
      assert_equal "repository owned pointer\n", File.read(File.join(root, '.agents/shaka.md'))
      assert_equal yaml, File.read(File.join(root, '.agents/agent-workflow.yml'))
    end
  end

  def test_apply_refuses_a_new_configuration_beside_the_legacy_destination
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      modern = File.join(root, '.agents/shaka/config.yml')
      FileUtils.mkdir_p(File.dirname(modern))
      File.write(modern, "version: 1\n")
      before = snapshot(root)

      _output, error, status = migrate(root, sha, '--apply')

      refute_predicate status, :success?
      assert_match(%r{\.agents/agent-workflow.yml.*\.agents/shaka/config.yml}, error)
      assert_equal before, snapshot(root)
    end
  end

  def test_apply_restores_original_contract_mode
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      yaml = File.join(root, '.agents/agent-workflow.yml')
      File.chmod(0o600, yaml)
      File.chmod(0o644, File.join(root, '.agents/bin/validate'))
      migrate(root, sha, '--apply')

      assert_equal 0o600, File.stat(yaml).mode & 0o777
    end
  end

  def test_apply_writes_a_typed_seam_and_keeps_repository_wrappers
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      wrapper = File.read(File.join(root, '.agents/bin/validate'))
      report = migrate_report(root, sha, '--apply')
      config = YAML.safe_load_file(File.join(root, '.agents/agent-workflow.yml'))

      assert_typed_apply(root, report, config, wrapper)
    end
  end

  private

  def assert_typed_apply(root, report, config, wrapper)
    assert_equal 'apply', report.fetch('mode')
    assert_retired_keys_removed(config)
    assert_equal 'ask', config.dig('merge', 'preference')
    assert_pointer_and_wrappers(root, wrapper)
    resolved = File.realpath(root)
    assert_includes report.fetch('rollback'), "git -C #{resolved}"
    assert_includes report.fetch('rollback'), "rm -f #{File.join(resolved, '.agents/shaka.md')}"
  end

  def assert_retired_keys_removed(config)
    assert_equal 1, config.fetch('version')
    refute config.key?('commands')
    refute config.key?('protection')
    refute config.dig('merge', 'method')
  end

  def assert_pointer_and_wrappers(root, wrapper)
    assert_includes File.read(File.join(root, '.agents/shaka.md')), 'Generated by shaka seam migrate.'
    refute_includes File.read(File.join(root, '.agents/shaka.md')), 'Generated by `shaka seam init`'
    refute_includes File.read(File.join(root, '.agents/shaka.md')), '.agents/README.md'
    assert_equal wrapper, File.read(File.join(root, '.agents/bin/validate'))
  end
end

class SeamMigratePolicyOverlayTest < Minitest::Test
  include SeamMigrateHelpers

  def test_matching_policy_flags_keep_established_reviewers
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      report = migrate_report(root, sha, '--review-policy', 'none', '--merge-preference', 'ask')
      reviewers = report.dig('established', 'review', 'local_review_agents')

      assert_equal 'none', report.dig('established', 'review', 'required')
      assert_equal 'anthropic', reviewers.dig(0, 'provider')
      assert_equal 'openai', reviewers.dig(1, 'provider')
    end
  end

  def test_policy_flags_cannot_override_established_merge_preference
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      _output, error, status = migrate(root, sha, '--apply', '--merge-preference', 'auto')

      refute_predicate status, :success?
      assert_includes error, 'merge.preference'
    end
  end

  def test_non_hash_branches_block
    with_legacy_repository('react_on_rails_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('branches' => '{login}-cursor/1-demo') }

      assert_includes migrate_report(root, sha).fetch('blocking'), 'branches'
    end
  end

  def test_unsupported_predecessor_version_blocks
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('version' => 2) }

      assert_includes migrate_report(root, sha).fetch('blocking'), 'version'
    end
  end

  def test_missing_review_check_blocks_before_apply
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) do |data|
        data.merge('review' => { 'required' => 'always' })
      end

      assert_includes migrate_report(root, sha).fetch('blocking'), 'review.ci_review_jobs'
    end
  end

  def test_review_check_flag_clears_blocking
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => always_review_without_check(data)) }
      report = migrate_report(root, sha, *review_check_flags)

      refute_includes report.fetch('blocking'), 'review.ci_review_jobs'
      assert_equal ['example-review'], report.dig('established', 'review', 'ci_review_jobs')
    end
  end

  def test_review_check_flag_applies_the_named_check
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => always_review_without_check(data)) }
      applied = migrate_report(root, sha, '--apply', *review_check_flags)
      config = YAML.safe_load_file(File.join(root, '.agents/agent-workflow.yml'))

      assert_equal 'apply', applied.fetch('mode')
      assert_equal ['example-review'], config.dig('review', 'ci_review_jobs')
    end
  end

  def test_old_and_new_spellings_of_one_review_field_block
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => colliding_review(data)) }
      blocking = migrate_report(root, sha).fetch('blocking')

      assert_includes blocking, 'review.check (collides with review.ci_review_jobs)'
      assert_includes blocking, 'review.reviewers (collides with review.local_review_agents)'
    end
  end

  def test_setup_collision_names_the_setup_adapter
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('commands' => setup_collision_commands) }
      collision = migrate_report(root, sha).fetch('command_collisions').find { |item| item.fetch('role') == 'setup' }

      refute_nil collision
      assert_includes collision.fetch('temporary_behavior'), 'bin/bootstrap'
      refute_includes collision.fetch('temporary_behavior'), 'validate'
    end
  end

  def test_non_mapping_yaml_reports_blocking_without_a_stack_trace
    with_legacy_repository('react_on_rails_shape.yml') do |root, _sha|
      File.write(File.join(root, '.agents/agent-workflow.yml'), "---\n- not-a-mapping\n")
      sha = commit_repository(root)
      output, error, status = migrate(root, sha)

      assert_predicate status, :success?, error
      assert_includes JSON.parse(output).fetch('blocking'), '.agents/agent-workflow.yml'
    end
  end

  def setup_collision_commands
    { 'setup' => 'bin/bootstrap', 'validate' => '.agents/bin/validate', 'test' => '.agents/bin/test' }
  end

  def colliding_review(data)
    reviewers = data.dig('review', 'reviewers').map(&:dup)
    { 'required' => 'always', 'ci_review_jobs' => ['claude-review'], 'check' => 'claude-review',
      'local_review_agents' => reviewers, 'reviewers' => reviewers.map(&:dup) }
  end

  def always_review_without_check(data)
    { 'required' => 'always', 'reviewers' => data.dig('review', 'reviewers') }
  end

  def review_check_flags
    ['--review-policy', 'always', '--ci-review-job', 'example-review']
  end
end

class SeamMigratePreviousCiJobKeyTest < Minitest::Test
  include SeamMigrateHelpers

  def test_previous_ci_agent_list_becomes_ci_jobs
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) do |data|
        data.merge('review' => { 'required' => 'always', 'ci_review_agents' => ['claude-review'],
                                 'reviewers' => data.dig('review', 'reviewers') })
      end
      report = migrate_report(root, sha)

      assert_empty report.fetch('blocking')
      assert_equal ['claude-review'], report.dig('established', 'review', 'ci_review_jobs')
    end
  end

  def test_previous_ci_agent_scalar_names_the_required_list_shape
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) do |data|
        data.merge('review' => { 'required' => 'always', 'ci_review_agents' => 'claude-review',
                                 'reviewers' => data.dig('review', 'reviewers') })
      end
      report = migrate_report(root, sha)

      assert_includes report.fetch('blocking'),
                      'review.ci_review_agents must be a list of CI job names before moving to review.ci_review_jobs'
    end
  end
end

class SeamMigrateCiJobListTest < Minitest::Test
  include SeamMigrateHelpers

  def test_a_string_under_the_current_ci_key_blocks
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => scalar_current_review(data)) }
      report = migrate_report(root, sha)

      assert_includes report.fetch('blocking'), 'review.ci_review_jobs'
      assert_nil report.dig('established', 'review', 'ci_review_jobs')
    end
  end

  def test_a_legacy_check_string_becomes_one_list_entry
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => legacy_check_review(data, 'check')) }
      report = migrate_report(root, sha)

      refute_includes report.fetch('blocking'), 'review.ci_review_jobs'
      assert_equal ['claude-review'], report.dig('established', 'review', 'ci_review_jobs')
    end
  end

  def test_a_string_ci_key_still_blocks_when_review_is_not_required
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => unrequired_scalar_review(data)) }
      blocking = migrate_report(root, sha).fetch('blocking')

      assert_includes blocking, 'review.ci_review_jobs must be a list of CI job names'
    end
  end

  def test_a_blank_ci_job_name_blocks_the_plan
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => blank_ci_review(data)) }
      blocking = migrate_report(root, sha).fetch('blocking')

      assert_includes blocking, 'review.ci_review_jobs[0] must be a non-empty string'
    end
  end

  def test_ci_review_jobs_block_when_review_is_not_required
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => unrequired_ci_review(data)) }
      blocking = migrate_report(root, sha).fetch('blocking')

      assert_includes blocking, 'review.ci_review_jobs must be omitted when review.required is none'
    end
  end

  def test_an_array_under_a_legacy_check_key_blocks
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => legacy_array_review(data)) }
      report = migrate_report(root, sha)

      assert_includes report.fetch('blocking'), 'review.check'
      assert_nil report.dig('established', 'review', 'ci_review_jobs')
    end
  end

  def test_a_legacy_key_listed_first_names_that_key_in_the_collision
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => legacy_first_collision(data)) }
      blocking = migrate_report(root, sha).fetch('blocking')

      assert_includes blocking, 'review.check (collides with review.ci_review_jobs)'
      refute_includes blocking, 'review.ci_review_jobs (collides with review.ci_review_jobs)'
    end
  end

  def test_a_legacy_github_action_check_string_becomes_one_list_entry
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => legacy_check_review(data, 'github_action_check')) }
      report = migrate_report(root, sha)

      refute_includes report.fetch('blocking'), 'review.ci_review_jobs'
      assert_equal ['claude-review'], report.dig('established', 'review', 'ci_review_jobs')
    end
  end

  def scalar_current_review(data)
    { 'required' => 'always', 'ci_review_jobs' => 'claude-review',
      'reviewers' => data.dig('review', 'reviewers') }
  end

  def blank_ci_review(data)
    { 'required' => 'always', 'ci_review_jobs' => [''], 'reviewers' => data.dig('review', 'reviewers') }
  end

  def unrequired_scalar_review(data)
    { 'required' => 'none', 'ci_review_jobs' => 'claude-review', 'reviewers' => data.dig('review', 'reviewers') }
  end

  def unrequired_ci_review(data)
    { 'required' => 'none', 'ci_review_jobs' => ['claude-review'],
      'reviewers' => data.dig('review', 'reviewers') }
  end

  def legacy_array_review(data)
    { 'required' => 'always', 'check' => ['claude-review'], 'reviewers' => data.dig('review', 'reviewers') }
  end

  def legacy_first_collision(data)
    reviewers = data.dig('review', 'reviewers').map(&:dup)
    { 'required' => 'always', 'check' => 'claude-review', 'ci_review_jobs' => ['claude-review'],
      'reviewers' => reviewers }
  end

  def legacy_check_review(data, key)
    { 'required' => 'always', key => 'claude-review', 'reviewers' => data.dig('review', 'reviewers') }
  end
end

class SeamMigrateOptionalCommandTest < Minitest::Test
  include SeamMigrateHelpers

  def test_optional_command_collision_names_the_hyphenated_entry
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('commands' => optional_collision_commands) }
      collisions = migrate_report(root, sha).fetch('command_collisions')
      collision = collisions.find { |item| item.fetch('role') == 'validate_local' }

      refute_nil collision
      assert_includes collision.fetch('temporary_behavior'), 'script/fast'
      assert_includes collision.fetch('temporary_behavior'), '.agents/bin/validate-local'
    end
  end

  def test_missing_optional_entry_point_blocks_apply
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('commands' => optional_collision_commands) }
      before = snapshot(root)
      report = migrate_report(root, sha)

      assert_includes report.fetch('blocking'), '.agents/bin/validate-local'
      _output, error, status = migrate(root, sha, '--apply')
      refute_predicate status, :success?
      assert_includes error, 'validate-local'
      assert_equal before, snapshot(root)
    end
  end

  def test_worktree_optional_entry_clears_blocking
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('commands' => optional_collision_commands) }
      install_optional_wrapper(root)
      report = migrate_report(root, sha)

      refute_includes report.fetch('blocking'), '.agents/bin/validate-local'
      assert_equal 'apply', migrate_report(root, sha, '--apply').fetch('mode')
    end
  end

  def test_from_ref_optional_entry_does_not_replace_the_worktree
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      install_optional_wrapper(root)
      sha = rewrite_yaml(root) { |data| data.merge('commands' => optional_collision_commands) }
      File.delete(File.join(root, '.agents/bin/validate-local'))

      assert_includes migrate_report(root, sha).fetch('blocking'), '.agents/bin/validate-local'
    end
  end

  def test_operational_command_paths_are_not_removable
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('commands' => operational_commands) }

      refute_includes migrate_report(root, sha).fetch('adapters_eligible_for_removal'), '.agents/bin/docs'
    end
  end

  def optional_collision_commands
    {
      'setup' => '.agents/bin/setup',
      'validate' => '.agents/bin/validate',
      'test' => '.agents/bin/test',
      'validate_local' => 'script/fast'
    }
  end

  def operational_commands
    optional_collision_commands.merge('docs' => '.agents/bin/docs')
  end

  def install_optional_wrapper(root)
    path = File.join(root, '.agents/bin/validate-local')
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
  end
end

class SeamMigrateRecoveryLocationsTest < Minitest::Test
  include SeamMigrateHelpers

  def test_previous_privacy_choice_survives_the_rename
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('recovery' => { 'workspace_path' => false }) }
      report = migrate_report(root, sha)

      assert_empty report.fetch('blocking')
      assert_equal({ 'include_locations' => false }, report.dig('established', 'wip'))
    end
  end

  def test_empty_previous_group_keeps_default_location_behavior
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('recovery' => {}) }
      report = migrate_report(root, sha)

      assert_empty report.fetch('blocking')
      assert_equal({}, report.dig('established', 'wip'))
    end
  end

  def test_intermediate_location_name_preserves_the_privacy_choice
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('recovery' => { 'publish_locations' => false }) }
      report = migrate_report(root, sha)

      assert_empty report.fetch('blocking')
      assert_equal({ 'include_locations' => false }, report.dig('established', 'wip'))
    end
  end

  def test_two_old_location_names_block_instead_of_choosing_one
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) do |data|
        data.merge('recovery' => { 'workspace_path' => false, 'publish_locations' => true })
      end

      refute_empty migrate_report(root, sha).fetch('blocking')
    end
  end

  def test_plan_moves_to_agent_instructions_instead_of_being_silently_discarded
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('plan' => 'requirements.md') }
      report = migrate_report(root, sha)

      assert_includes report.fetch('moved_to_agents'), 'plan'
      refute report.fetch('established').key?('plan')
    end
  end

  def test_applied_migration_keeps_locations_private
    with_legacy_repository('control_plane_flow_shape.yml') do |root, sha|
      migrate_report(root, sha, '--apply')
      config = YAML.safe_load_file(File.join(root, '.agents/agent-workflow.yml'))

      assert_equal({ 'include_locations' => false }, config.fetch('wip'))
    end
  end

  def test_conflicting_location_keys_block_instead_of_selecting_a_value
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) do |data|
        data.merge('recovery' => { 'workspace_path' => false }, 'wip' => { 'include_locations' => true })
      end

      assert_includes migrate_report(root, sha).fetch('blocking'),
                      'recovery (collides with wip)'
    end
  end
end

class SeamMigrateReviewWaitTest < Minitest::Test
  include SeamMigrateHelpers

  def test_migration_preserves_all_and_conservatively_maps_swift_to_one
    { 'swift' => 'one', 'thorough' => 'all' }.each do |pace, expected|
      with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
        sha = rewrite_yaml(root) { |data| data.merge('review' => data.fetch('review').merge('pace' => pace)) }
        migrate_report(root, sha, '--apply')
        config = YAML.safe_load_file(File.join(root, '.agents/agent-workflow.yml'))

        assert_equal expected, config.dig('review', 'ci_review_wait')
        refute config.fetch('review').key?('pace')
      end
    end
  end

  def test_conflicting_wait_keys_block_in_either_order
    [{ 'pace' => 'thorough', 'ci_review_wait' => 'none' },
     { 'ci_review_wait' => 'none', 'pace' => 'thorough' }].each do |settings|
      with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
        sha = rewrite_yaml(root) { |data| data.merge('review' => data.fetch('review').merge(settings)) }

        assert_includes migrate_report(root, sha).fetch('blocking'),
                        'review.pace (collides with review.ci_review_wait)'
      end
    end
  end

  def test_unknown_pace_blocks_instead_of_disabling_the_wait
    with_legacy_repository('control_plane_flow_shape.yml') do |root, _sha|
      sha = rewrite_yaml(root) { |data| data.merge('review' => data.fetch('review').merge('pace' => 'fast')) }

      assert_includes migrate_report(root, sha).fetch('blocking'), 'review.pace must be swift or thorough'
    end
  end
end
