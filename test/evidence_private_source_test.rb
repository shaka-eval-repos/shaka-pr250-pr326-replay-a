# frozen_string_literal: true

require_relative 'evidence_fixture'

class EvidencePrivateSourceTest < Minitest::Test
  include EvidenceFixture

  def test_private_source_result_uses_local_settings_without_trust_promotion
    with_private_checkout do |root, ref, _private_dir|
      result = run_check(root, ref)
      assert_equal 'private/local', result.fetch('source_kind')
      assert_equal 'completed', result.fetch('status')
      assert_equal 'bound', bind(root, ref, ref, result).fetch('status')
    end
  end

  def test_ignored_private_input_changed_during_run_invalidates_result_without_tree_change
    with_private_checkout do |root, ref, private_dir|
      File.write(File.join(private_dir, 'bin/test'), "#!/bin/sh\necho changed > .agents/shaka/extra\n")
      result = run_check(root, ref, expected_exit: 1)
      assert_equal 'not_completed', result.fetch('status')
      assert_equal result.fetch('tested_tree'), result.fetch('tree_after')
      refute_equal result.fetch('settings'), result.fetch('settings_after')
    end
  end

  private

  def with_private_checkout
    Dir.mktmpdir('shaka-private-evidence') do |root|
      setup_private_checkout(root)
      yield root, git(root, 'rev-parse', 'HEAD'), File.join(root, '.agents/shaka')
    end
  end

  def setup_private_checkout(root)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    File.write(File.join(root, 'feature'), 'first')
    git(root, 'add', 'feature')
    commit(root)
    directory = File.join(root, '.agents/shaka')
    FileUtils.mkdir_p(File.join(directory, 'bin'))
    File.write(File.join(directory, 'config.yml'), YAML.dump(config))
    write_private_commands(directory)
    File.write(File.join(root, '.git/info/exclude'), "/.agents/shaka/\n")
  end

  def write_private_commands(directory)
    %w[setup test validate].each do |name|
      path = File.join(directory, 'bin', name)
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
  end
end
