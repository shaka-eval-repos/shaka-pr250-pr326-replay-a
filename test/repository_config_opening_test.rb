# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'shaka/trusted_config_source'

class RepositoryConfigOpeningTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_external_opening_checks_default_to_enabled
    with_repository do |root|
      config = Shaka::RepositoryConfig.load(root:)
      assert_equal({ 'external_enabled' => true }, config.opening_check)
      assert_equal config.opening_check, config.to_h.fetch('opening_check')
    end
  end

  def test_effective_contract_includes_the_default_with_a_prompt_file
    with_repository('opening_check' => { 'prompt_file' => '.agents/opening.md' }) do |root|
      File.write(File.join(root, '.agents/opening.md'), 'Parse this opening.')
      assert_equal({ 'external_enabled' => true, 'prompt_file' => '.agents/opening.md' },
                   Shaka::RepositoryConfig.load(root:).to_h.fetch('opening_check'))
    end
  end

  def test_rejects_non_boolean_or_unknown_opening_settings
    [{ 'external_enabled' => 'yes' }, { 'enabled' => true }, { 'foo' => true }, true].each do |opening|
      with_repository('opening_check' => opening) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }
        assert_includes error.message, 'opening_check'
      end
    end
  end

  def test_rejects_an_invalid_opening_prompt_path
    with_repository('opening_check' => { 'prompt_file' => '../outside.md' }) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }
      assert_equal 'opening_check.prompt_file must be a path inside the repository', error.message
    end
  end

  def test_rejects_a_missing_local_opening_prompt
    with_repository('opening_check' => { 'prompt_file' => '.agents/missing.md' }) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }
      assert_includes error.message, 'opening_check.prompt_file does not exist'
    end
  end

  def test_trusted_prompt_comes_from_the_pinned_commit
    with_repository('opening_check' => { 'external_enabled' => true, 'prompt_file' => '.agents/opening.md' }) do |root|
      File.write(File.join(root, '.agents/opening.md'), 'Parse the first sentence.')
      commit(root)
      source = Shaka::TrustedConfigSource.new(root:)
      config = source.load('HEAD')
      File.write(File.join(root, '.agents/opening.md'), 'Candidate replacement.')
      assert_equal 'Parse the first sentence.', source.opening_prompt(config)
    end
  end

  def test_trusted_prompt_resolves_a_symlinked_directory
    with_repository('opening_check' => { 'external_enabled' => true,
                                         'prompt_file' => '.agents/opening-link/prompt.md' }) do |root|
      FileUtils.mkdir_p(File.join(root, 'prompts'))
      File.write(File.join(root, 'prompts/prompt.md'), 'Parse this opening.')
      File.symlink('../prompts', File.join(root, '.agents/opening-link'))
      commit(root)
      source = Shaka::TrustedConfigSource.new(root:)
      assert_equal 'Parse this opening.', source.opening_prompt(source.load('HEAD'))
    end
  end

  def test_trusted_prompt_rejects_a_directory
    with_repository('opening_check' => { 'prompt_file' => '.agents/opening' }) do |root|
      Dir.mkdir(File.join(root, '.agents/opening'))
      File.write(File.join(root, '.agents/opening/note.md'), 'text')
      commit(root)
      assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.load(root:, ref: 'HEAD') }
    end
  end

  def test_trusted_prompt_rejects_an_oversize_file
    with_repository('opening_check' => { 'prompt_file' => '.agents/opening.md' }) do |root|
      File.write(File.join(root, '.agents/opening.md'), 'x' * 100_001)
      commit(root)
      assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.load(root:, ref: 'HEAD') }
    end
  end

  private

  def commit(root)
    system('git', '-C', root, 'init', '-q', exception: true)
    system('git', '-C', root, 'add', '.', exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '-qm', 'trusted', exception: true)
  end
end
