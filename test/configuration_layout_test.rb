# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'configuration_layout_fixture'
require 'shaka/configuration'

class ConfigurationLayoutTest < Minitest::Test
  include ConfigurationLayoutFixture

  def test_new_layout_loads_from_worktree_and_trusted_commit
    with_new_layout do |root|
      local = Shaka::Configuration.worktree(root:)
      assert_equal '.agents/shaka/bin/validate', local.command('validate')

      commit_fixture(root)
      trusted = Shaka::Configuration.trusted(root:, ref: 'HEAD')
      assert_equal '.agents/shaka/bin/validate', trusted.command('validate')
      assert_equal '.agents/shaka/config.yml', trusted.config_path
    end
  end

  def test_both_contracts_fail_without_precedence
    with_new_layout do |root|
      File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(config))
      assert_both_paths { Shaka::Configuration.worktree(root:) }
      commit_fixture(root)
      assert_both_paths { Shaka::Configuration.trusted(root:, ref: 'HEAD') }
    end
  end

  private

  def assert_both_paths(&)
    error = assert_raises(Shaka::Error, &)
    assert_includes error.message, '.agents/agent-workflow.yml'
    assert_includes error.message, '.agents/shaka/config.yml'
  end
end

class ConfigurationCandidateLayoutTest < Minitest::Test
  include ConfigurationLayoutFixture

  def test_new_config_never_uses_legacy_required_command
    with_new_layout do |root|
      FileUtils.mv(File.join(root, '.agents/shaka/bin/validate'), File.join(root, '.agents/bin/validate'))
      error = assert_raises(Shaka::Error) { Shaka::Configuration.worktree(root:) }
      assert_includes error.message, '.agents/shaka/bin/validate'
    end
  end

  def test_trusted_legacy_policy_uses_new_candidate_commands
    with_repository do |root|
      commit_fixture(root)
      move_to_new_layout(root)

      assert_legacy_policy_new_candidate(Shaka::Configuration.trusted(root:, ref: 'HEAD'))
      FileUtils.rm(File.join(root, '.agents/shaka/bin/validate'))
      error = assert_raises(Shaka::Error) { Shaka::Configuration.trusted(root:, ref: 'HEAD') }
      assert_includes error.message, '.agents/shaka/bin/validate'
    end
  end

  def test_trusted_new_policy_uses_legacy_candidate_commands
    with_new_layout do |root|
      commit_fixture(root)
      move_to_legacy_layout(root)

      trusted = Shaka::Configuration.trusted(root:, ref: 'HEAD')
      assert_equal '.agents/shaka/config.yml', trusted.to_h.dig('paths', 'policy_configuration')
      assert_equal '.agents/agent-workflow.yml', trusted.to_h.dig('paths', 'candidate_configuration')
      assert_equal '.agents/bin/validate', trusted.command('validate')
    end
  end

  private

  def assert_legacy_policy_new_candidate(trusted)
    paths = trusted.to_h.fetch('paths')
    assert_equal '.agents/agent-workflow.yml', paths.fetch('policy_configuration')
    assert_equal '.agents/shaka/config.yml', paths.fetch('candidate_configuration')
    assert_equal '.agents/bin', paths.fetch('trusted_command_directory')
    assert_equal '.agents/shaka/bin', paths.fetch('candidate_command_directory')
    assert_equal '.agents/shaka/bin/validate', trusted.command('validate')
  end
end

class ConfigurationLayoutSafetyTest < Minitest::Test
  include ConfigurationLayoutFixture

  def test_unselected_optional_commands_are_not_discovered
    with_new_layout do |root|
      path = File.join(root, '.agents/bin/validate-local')
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
      refute Shaka::Configuration.worktree(root:).commands.key?('validate_local')
    end
  end

  def test_legacy_config_does_not_use_new_command_directory
    with_repository do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/shaka'))
      FileUtils.mv(File.join(root, '.agents/bin'), File.join(root, '.agents/shaka/bin'))
      error = assert_raises(Shaka::Error) { Shaka::Configuration.worktree(root:) }
      assert_includes error.message, '.agents/bin/setup'
    end
  end

  def test_new_layout_preserves_legacy_optional_name_validation
    with_new_layout do |root|
      path = File.join(root, '.agents/shaka/bin/validate_local')
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
      error = assert_raises(Shaka::Error) { Shaka::Configuration.worktree(root:) }
      assert_includes error.message, '.agents/shaka/bin/validate-local'
    end
  end

  def test_new_layout_fixture_commands_execute_from_repository_root
    with_new_layout do |root|
      %w[setup validate test].each do |name|
        path = File.join(root, '.agents/shaka/bin', name)
        File.write(path, "#!/bin/sh\ncd \"$(dirname \"$0\")/../../..\"\npwd\n")
        output, status = Open3.capture2e(path, chdir: root)
        assert_predicate status, :success?, output
        assert File.identical?(root, output.strip)
      end
    end
  end

  def test_new_config_symlink_is_rejected_locally_and_at_trusted_commit
    with_new_layout do |root|
      config_path = File.join(root, '.agents/shaka/config.yml')
      FileUtils.mv(config_path, File.join(root, 'config.yml'))
      File.symlink('../../config.yml', config_path)

      error = assert_raises(Shaka::Error) { Shaka::Configuration.worktree(root:) }
      assert_includes error.message, '.agents/shaka/config.yml'
      commit_fixture(root)
      error = assert_raises(Shaka::Error) { Shaka::Configuration.trusted(root:, ref: 'HEAD') }
      assert_includes error.message, '.agents/shaka/config.yml'
    end
  end

  def test_new_command_symlink_keeps_existing_target_rules
    with_new_layout do |root|
      validate = File.join(root, '.agents/shaka/bin/validate')
      FileUtils.rm(validate)
      File.symlink('test', validate)
      assert_equal '.agents/shaka/bin/validate', Shaka::Configuration.worktree(root:).command('validate')
      commit_fixture(root)
      assert_equal '.agents/shaka/bin/validate', Shaka::Configuration.trusted(root:, ref: 'HEAD').command('validate')
    end
  end

  def test_new_command_requires_executable_mode_at_trusted_commit
    with_new_layout do |root|
      File.chmod(0o644, File.join(root, '.agents/shaka/bin/validate'))
      commit_fixture(root)
      error = assert_raises(Shaka::Error) { Shaka::Configuration.trusted(root:, ref: 'HEAD') }
      assert_includes error.message, '.agents/shaka/bin/validate'
    end
  end

  def test_new_config_keeps_repository_relative_prompt_paths
    with_new_layout do |root|
      write_new_prompt_config(root)
      assert_equal '.agents/shaka/review-prompt.md', Shaka::Configuration.worktree(root:).review.fetch('prompt_file')
      commit_fixture(root)
      assert_equal '.agents/shaka/review-prompt.md',
                   Shaka::Configuration.trusted(root:, ref: 'HEAD').review.fetch('prompt_file')
    end
  end

  def test_no_configuration_does_not_select_commands_from_both_directories
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, '.agents/bin'))
      FileUtils.mkdir_p(File.join(root, '.agents/shaka/bin'))
      assert_raises(Shaka::Error) { Shaka::Configuration.worktree(root:) }
    end
  end

  def test_read_operations_do_not_change_files
    with_new_layout do |root|
      before = Dir.glob(File.join(root, '**/*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.to_h do |path|
        [path, File.binread(path)]
      end
      Shaka::Configuration.worktree(root:)
      after = before.keys.to_h { |path| [path, File.binread(path)] }
      assert_equal before, after
    end
  end
end

class ConfigurationInvalidLayoutTest < Minitest::Test
  include ConfigurationLayoutFixture

  def test_non_file_contract_reports_its_actual_type_requirement
    with_new_layout do |root|
      path = File.join(root, '.agents/shaka/config.yml')
      FileUtils.rm(path)
      FileUtils.mkdir_p(path)
      error = assert_raises(Shaka::Error) { Shaka::Configuration.worktree(root:) }
      assert_includes error.message, 'must be a regular file'
      refute_includes error.message, 'symlink'
    end
  end

  def test_unrelated_file_at_new_layout_parent_keeps_legacy_config_usable
    with_repository do |root|
      File.write(File.join(root, '.agents/shaka'), "unrelated tool\n")
      assert_equal '.agents/bin/validate', Shaka::Configuration.worktree(root:).command('validate')
    end
  end
end

class ConfigurationReviewLayoutTest < Minitest::Test
  include ConfigurationLayoutFixture

  def test_review_settings_read_new_config_at_trusted_commit
    with_new_layout do |root|
      write_new_prompt_config(root)
      commit_fixture(root)
      capture = method(:capture_git)
      probe = ->(*arguments) { Open3.capture3('git', *arguments, chdir: root) }
      assert Shaka::Configuration.contract_at_commit?(root:, ref: 'HEAD', git: probe)
      review = Shaka::Configuration.review_at_commit(root:, ref: 'HEAD', git: 'git', capture:, probe:)
      assert_equal '.agents/shaka/review-prompt.md', review.fetch('prompt_file')
    end
  end

  private

  def capture_git(*)
    output, error, status = Open3.capture3(*)
    raise error unless status.success?

    output
  end
end
