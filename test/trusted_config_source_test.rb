# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'rbconfig'
require 'shaka/trusted_config_source'

class TrustedConfigSourceTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_file_can_report_its_own_errors_when_required_directly
    library = File.expand_path('../skills/shaka/lib', __dir__)
    script = <<~RUBY
      require 'shaka/trusted_config_source'
      Shaka::TrustedConfigSource.new(root: Dir.pwd).load('missing-ref')
    RUBY

    output, status = Open3.capture2e(RbConfig.ruby, '-I', library, '-e', script)

    refute_predicate status, :success?
    assert_includes output, 'Shaka::Error'
    refute_includes output, 'uninitialized constant'
  end
end

module TrustedConfigSourceRepositoryHelpers
  private

  def write_executable(root, relative)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
  end

  def commit_repository(root)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    system('git', '-C', root, 'add', '.', exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'trusted', exception: true)
  end
end

class TrustedConfigSourceSymlinkTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include TrustedConfigSourceRepositoryHelpers

  def test_accepts_a_trusted_optional_symlink
    with_repository do |root|
      File.symlink('validate', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      config = Shaka::TrustedConfigSource.new(root:).load('HEAD')
      assert_equal '.agents/bin/validate-local', config.command('validate_local')
    end
  end

  def test_accepts_a_trusted_optional_symlink_chain
    with_repository do |root|
      File.symlink('validate', File.join(root, '.agents/bin/validate-hop'))
      File.symlink('validate-hop', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      config = Shaka::TrustedConfigSource.new(root:).load('HEAD')
      assert_equal '.agents/bin/validate-local', config.command('validate_local')
    end
  end

  def test_accepts_a_trusted_optional_target_through_a_directory_symlink
    with_repository do |root|
      File.symlink('bin', File.join(root, '.agents/current'))
      File.symlink('../current/validate', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      config = Shaka::TrustedConfigSource.new(root:).load('HEAD')
      assert_equal '.agents/bin/validate-local', config.command('validate_local')
    end
  end

  def test_resolves_parent_segments_after_expanding_a_directory_symlink
    with_repository do |root|
      write_executable(root, 'tools/validate')
      FileUtils.mkdir_p(File.join(root, 'tools/bin'))
      File.write(File.join(root, 'tools/bin/.keep'), '')
      File.symlink('tools/bin', File.join(root, 'alias'))
      File.symlink('../../alias/../validate', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      config = Shaka::TrustedConfigSource.new(root:).load('HEAD')
      assert_equal '.agents/bin/validate-local', config.command('validate_local')
    end
  end

  def test_accepts_revisiting_a_symlink_after_ascending
    with_repository do |root|
      write_executable(root, 'tools/validate')
      File.symlink('tools', File.join(root, 'alias'))
      File.symlink('../../alias/../alias/validate', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      config = Shaka::TrustedConfigSource.new(root:).load('HEAD')
      assert_equal '.agents/bin/validate-local', config.command('validate_local')
    end
  end

  def test_rejects_a_trusted_symlink_that_traverses_a_regular_file
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      File.symlink('validate/../validate', path)
      commit_repository(root)
      FileUtils.rm(path)
      File.symlink('validate', path)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'must target a tracked executable file: .agents/bin/validate'
    end
  end

  def test_rejects_a_trusted_symlink_with_a_trailing_slash_on_a_file
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      File.symlink('validate/', path)
      commit_repository(root)
      FileUtils.rm(path)
      File.symlink('validate', path)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'must target a tracked executable file: .agents/bin/validate'
    end
  end

  def test_rejects_a_trusted_optional_symlink_cycle
    with_repository do |root|
      File.symlink('validate-hop', File.join(root, '.agents/bin/validate-local'))
      File.symlink('validate-local', File.join(root, '.agents/bin/validate-hop'))
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'Trusted command symlink cycle'
    end
  end

  def test_rejects_an_absolute_trusted_optional_symlink_target
    with_repository do |root|
      File.symlink('/tmp/validate', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'must target a file inside the repository'
    end
  end

  def test_rejects_a_trusted_optional_symlink_target_above_the_repository
    with_repository do |root|
      File.symlink('../../../validate', File.join(root, '.agents/bin/validate-local'))
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'must stay inside the repository'
    end
  end
end

class TrustedConfigSourceCommandEntryTest < Minitest::Test
  include RepositoryConfigTestHelpers
  include TrustedConfigSourceRepositoryHelpers

  def test_rejects_a_trusted_ref_that_omits_a_required_command
    with_repository do |root|
      FileUtils.rm(File.join(root, '.agents/bin/setup'))
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, '.agents/bin/setup is missing at trusted ref'
    end
  end

  def test_rejects_a_non_executable_trusted_optional_entry
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      File.write(path, "#!/bin/sh\nexit 0\n")
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, '.agents/bin/validate-local at'
      assert_includes message, 'must be an executable file or symlink'
    end
  end

  def test_rejects_a_legacy_optional_path_missing_its_standard_entry_point_on_the_trusted_ref
    with_repository do |root|
      legacy = File.join(root, '.agents/bin/validate_local')
      write_executable(root, '.agents/bin/validate_local')
      commit_repository(root)
      FileUtils.rm(legacy)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message,
                      '.agents/bin/validate_local requires the standard entry point .agents/bin/validate-local'
      assert_includes message, 'at trusted ref'
    end
  end

  def test_rejects_a_legacy_hosted_ci_path_missing_its_standard_entry_point_on_the_trusted_ref
    with_repository do |root|
      legacy = File.join(root, '.agents/bin/trigger_hosted_ci')
      write_executable(root, '.agents/bin/trigger_hosted_ci')
      commit_repository(root)
      FileUtils.rm(legacy)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, '.agents/bin/trigger_hosted_ci requires the standard entry point'
      assert_includes message, '.agents/bin/trigger-hosted-ci at trusted ref'
    end
  end

  def test_rejects_a_directory_at_a_trusted_optional_path
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      FileUtils.mkdir_p(path)
      File.write(File.join(path, '.keep'), '')
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'must be an executable file or symlink'
    end
  end

  def test_rejects_a_symlinked_trusted_command_directory
    with_repository do |root|
      agents = File.join(root, '.agents')
      FileUtils.mv(File.join(agents, 'bin'), File.join(root, 'scripts'))
      File.symlink('../scripts', File.join(agents, 'bin'))
      commit_repository(root)

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, '.agents/bin at'
      assert_includes message, 'must be a real directory, not a symlink'
    end
  end

  def test_reports_a_missing_trusted_command_directory_accurately
    with_repository do |root|
      FileUtils.rm_rf(File.join(root, '.agents/bin'))
      commit_repository(root)
      FileUtils.mkdir_p(File.join(root, '.agents/bin'))
      %w[setup validate test].each { |name| create_command(root, name) }

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, 'Cannot inspect .agents/bin at'
      refute_includes message, 'not a symlink'
    end
  end

  def test_rejects_a_trusted_optional_symlink_with_a_candidate_only_target
    with_repository do |root|
      path = File.join(root, '.agents/bin/validate-local')
      File.symlink('future', path)
      commit_repository(root)
      create_command(root, 'future')

      message = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.new(root:).load('HEAD') }.message
      assert_includes message, '.agents/bin/validate-local at'
      assert_includes message, 'must target a tracked executable file: .agents/bin/future'
    end
  end
end
