# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'shaka/repository_config'

class RepositoryConfigTest < Minitest::Test
  include RepositoryConfigTestHelpers

  ROOT = File.expand_path('..', __dir__)

  def test_this_repository_uses_a_valid_contract
    assert_instance_of Shaka::RepositoryConfig, Shaka::RepositoryConfig.load(root: ROOT)
  end

  def test_loads_the_repository_contract
    with_repository do |root|
      config = Shaka::RepositoryConfig.load(root:)

      assert_equal 'main', config.base_branch
      assert_equal '.agents/bin/validate', config.command('validate')
      assert_equal %w[setup test validate], config.commands.keys.sort
      assert_equal 'auto', config.merge.fetch('preference')
    end
  end

  def test_rejects_unknown_keys
    with_repository('surprise' => true) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'unknown .agents/agent-workflow.yml key: surprise'
    end
  end

  def test_rejects_an_unsupported_contract_version
    with_repository('version' => 2) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, 'version must be 1'
    end
  end

  def test_rejects_duplicate_keys_before_yaml_discards_them
    with_repository do |root|
      path = File.join(root, '.agents/agent-workflow.yml')
      File.write(path, File.read(path).sub('base_branch: main', "base_branch: main\nbase_branch: trunk"))

      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'duplicate key: base_branch'
    end
  end

  def test_external_policy_source_requires_trusted_command_availability
    with_repository do |root|
      source = File.read(File.join(root, '.agents/agent-workflow.yml'))
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:, source:) }

      assert_includes error.message, 'available_commands is required'
    end
  end

  def test_rejects_a_missing_command
    with_repository do |root|
      FileUtils.rm(File.join(root, '.agents/bin/validate'))

      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, '.agents/bin/validate does not exist'
    end
  end

  def test_rejects_a_command_symlink_outside_the_repository
    with_repository do |root|
      with_outside_validate_symlink(root) do
        message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
        assert_includes message, '.agents/bin/validate must resolve inside the repository'
      end
    end
  end

  def test_accepts_a_command_symlink_to_an_executable_inside_the_repository
    with_repository do |root|
      target = File.join(root, 'bin', 'validate')
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, target)
      path = File.join(root, '.agents/bin/validate')
      FileUtils.rm(path)
      File.symlink('../../bin/validate', path)

      assert_equal '.agents/bin/validate', Shaka::RepositoryConfig.load(root:).command('validate')
    end
  end

  def test_rejects_an_unsupported_merge_preference
    with_repository('merge' => merge_policy.merge('preference' => 'sometimes')) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, 'merge.preference must be ask or auto'
    end
  end

  def test_loads_optional_local_validation_and_hosted_ci_commands
    with_repository do |root|
      optional_commands.each_key { |name| create_command(root, name) }
      config = Shaka::RepositoryConfig.load(root:)
      actual = optional_commands.keys.map { |name| config.command(name) }

      assert_equal optional_commands.values, actual
    end
  end

  def test_a_hosted_ci_trigger_requires_local_validation
    with_repository do |root|
      create_command(root, 'trigger_hosted_ci')
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, '.agents/bin/trigger-hosted-ci requires .agents/bin/validate-local'
    end
  end
end

class RepositoryConfigRetiredSettingTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_rejects_configurable_command_paths
    with_repository('commands' => { 'validate' => '../validate' }) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'unknown .agents/agent-workflow.yml key: commands'
    end
  end

  def test_rejects_retired_fixed_merge_fields
    { 'method' => 'squash', 'release' => 'explicit_approval' }.each do |key, value|
      with_repository('merge' => merge_policy.merge(key => value)) do |root|
        message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
        assert_includes message, "merge.#{key} is no longer configurable"
        assert_includes message, 'skills/shaka/references/migration.md'
      end
    end
  end

  def test_rejects_retired_github_fact_fields
    { 'protection' => {}, 'trusted_actions' => ['actions/checkout'] }.each do |key, value|
      with_repository(key => value) do |root|
        message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
        assert_includes message, "#{key} moved out of the seam"
        assert_includes message, 'skills/shaka/references/migration.md'
      end
    end
  end
end

class RepositoryConfigOptionalCommandTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_rejects_a_symlinked_agents_directory
    with_repository do |root|
      agents = File.join(root, '.agents')
      target = File.join(root, 'metadata')
      FileUtils.mv(agents, target)
      File.symlink('metadata', agents)

      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, '.agents must be a real directory, not a symlink'
    end
  end

  def test_a_legacy_optional_path_requires_its_standard_entry_point
    with_repository do |root|
      legacy = File.join(root, '.agents/bin/validate_local')
      File.write(legacy, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, legacy)

      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, '.agents/bin/validate_local requires the standard entry point .agents/bin/validate-local'
    end
  end

  def test_candidate_only_optional_commands_must_still_form_a_valid_interface
    with_repository do |root|
      create_command(root, 'trigger_hosted_ci')
      source = File.read(File.join(root, '.agents/agent-workflow.yml'))

      message = assert_raises(Shaka::Error) do
        Shaka::RepositoryConfig.load(root:, source:, available_commands: [])
      end.message
      assert_includes message, '.agents/bin/trigger-hosted-ci requires .agents/bin/validate-local'
    end
  end

  def test_rejects_a_non_executable_optional_command
    with_repository do |root|
      create_command(root, 'validate_local')
      File.chmod(0o644, File.join(root, '.agents/bin/validate-local'))

      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, '.agents/bin/validate-local is not executable'
    end
  end

  def test_rejects_a_dangling_optional_command_symlink
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      File.symlink('../../bin/missing-validate-local', path)

      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
      assert_includes message, '.agents/bin/validate-local does not exist'
    end
  end
end

# The optional wip policy decides what an unfinished pull request may publish.
class RepositoryConfigWipTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_wip_defaults_to_publishing_locations
    with_repository do |root|
      assert_equal({ 'include_locations' => true }, Shaka::RepositoryConfig.load(root:).wip)
    end
  end

  def test_the_effective_contract_includes_the_wip_default
    with_repository do |root|
      assert_equal({ 'include_locations' => true }, Shaka::RepositoryConfig.load(root:).to_h.fetch('wip'))
    end
  end

  def test_a_repository_can_opt_out_of_publishing_locations
    with_repository('wip' => { 'include_locations' => false }) do |root|
      assert_equal({ 'include_locations' => false }, Shaka::RepositoryConfig.load(root:).wip)
    end
  end

  def test_plan_requires_migration_to_agent_instructions
    with_repository('plan' => 'requirements.md') do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'plan moved out of the seam'
    end
  end

  def test_the_previous_location_key_names_its_replacement
    with_repository('recovery' => { 'workspace_path' => false }) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'wip.include_locations'
    end
  end

  def test_rejects_an_unknown_wip_key
    with_repository('wip' => { 'workspace' => false }) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'unknown wip key: workspace'
    end
  end

  def test_rejects_a_wip_value_that_is_not_a_boolean
    with_repository('wip' => { 'include_locations' => 'yes' }) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'wip.include_locations must be true or false'
    end
  end

  def test_an_absent_base_branch_means_the_repository_default_branch
    with_repository('base_branch' => nil) do |root|
      assert_nil Shaka::RepositoryConfig.load(root:).base_branch
    end
  end

  def test_rejects_a_qualified_ref_git_alone_would_accept
    with_repository('base_branch' => 'refs/heads/main') do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, 'base_branch must be a branch name, not a qualified ref'
    end
  end

  def test_rejects_a_root_ref_name_git_alone_would_accept
    %w[@ FETCH_HEAD ORIG_HEAD MERGE_AUTOSTASH BISECT_EXPECTED_REV].each do |value|
      with_repository('base_branch' => value) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

        assert_includes error.message, 'base_branch must be a branch name, not a Git root ref'
      end
    end
  end

  def test_accepts_uppercase_below_the_top_level
    with_repository('base_branch' => 'release/RC1') do |root|
      assert_equal 'release/RC1', Shaka::RepositoryConfig.load(root:).base_branch
    end
  end

  def test_rejects_control_characters_before_spawning_git
    ["main\0evil", "main\revil"].each do |value|
      with_repository('base_branch' => value) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

        assert_includes error.message, 'base_branch must not contain control characters'
      end
    end
  end

  def test_rejects_a_base_branch_git_would_reject
    ['-not-a-branch', 'has space', 'ends.lock', 'a..b'].each do |value|
      with_repository('base_branch' => value) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

        assert_includes error.message, 'base_branch must be a valid Git branch name'
      end
    end
  end
end

class RepositoryConfigRequiredChecksTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_loads_seam_required_checks
    with_repository('merge' => merge_policy.merge('required_checks' => %w[checks lint])) do |root|
      assert_equal %w[checks lint], Shaka::RepositoryConfig.load(root:).merge.fetch('required_checks')
    end
  end

  def test_rejects_invalid_seam_required_checks
    { 'checks' => 'must be a list of check names', [] => 'must not be empty',
      [' '] => 'merge.required_checks[0] must be a non-empty string',
      %w[checks Checks] => 'merge.required_checks repeats checks' }.each do |value, expected|
      with_repository('merge' => merge_policy.merge('required_checks' => value)) do |root|
        message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message
        assert_includes message, expected
      end
    end
  end
end
