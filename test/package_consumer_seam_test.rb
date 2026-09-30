# frozen_string_literal: true

require_relative 'package_test_helpers'

class PackageConsumerSeamTest < Minitest::Test
  include PackageTestHelpers

  def test_installed_gem_accepts_a_valid_consumer_as_local_candidate
    install_gem
    with_consumer_seam do |root|
      output, error, status = capture_installed('seam', 'check', '--root', root, '--local')
      assert_predicate status, :success?, error
      payload = JSON.parse(output)
      assert_equal 'local/candidate', payload.dig('validation', 'mode')
      assert_false payload.dig('validation', 'grants_policy')
      assert_false payload.dig('validation', 'grants_merge_authority')
      refute_includes output, 'trusted/ref'
    end
  end

  def test_installed_gem_rejects_an_unknown_consumer_key
    assert_local_failure('unknown', 'surprise') do |root|
      write_consumer_yaml(root, consumer_seam.merge('surprise' => true))
    end
  end

  def test_installed_gem_rejects_duplicate_consumer_keys
    assert_local_failure('duplicate key') do |root|
      File.write(File.join(root, '.agents/agent-workflow.yml'), <<~YAML)
        version: 1
        version: 2
        review:
          required: none
        merge:
          preference: ask
      YAML
    end
  end

  def test_installed_gem_rejects_a_non_executable_consumer_script
    assert_local_failure('not executable') do |root|
      File.chmod(0o644, File.join(root, '.agents/bin/validate'))
    end
  end

  private

  def assert_local_failure(*snippets)
    install_gem
    with_consumer_seam do |root|
      yield root
      _output, error, status = capture_installed('seam', 'check', '--root', root, '--local')
      refute_predicate status, :success?
      snippets.each { |snippet| assert_includes error, snippet }
    end
  end
end
