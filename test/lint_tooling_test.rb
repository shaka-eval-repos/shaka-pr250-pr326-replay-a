# frozen_string_literal: true

require_relative 'test_helper'
require 'bundler'
require 'yaml'

class LintToolingTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  PROBE = <<~RUBY
    # frozen_string_literal: true
    class ProbeTest < Minitest::Test
      def test_probe
        assert [].empty?
      end
    end
  RUBY

  def test_rubocop_loads_minitest_and_performance_departments
    %w[Minitest/AssertEmpty Performance/StringReplacement].each do |cop|
      output, status = show_cops(cop)
      assert_predicate status, :success?, output
      assert_includes output, "#{cop}:\n"
    end
  end

  def test_dependabot_schedules_bundler_updates_at_the_repository_root
    updates = YAML.safe_load_file(File.join(ROOT, '.github', 'dependabot.yml')).fetch('updates')
    bundler = updates.find { |update| update['package-ecosystem'] == 'bundler' }

    refute_nil bundler, 'Dependabot must include a bundler ecosystem'
    assert_equal '/', bundler.fetch('directory')
    assert_equal 'weekly', bundler.fetch('schedule').fetch('interval')
  end

  def test_minitest_cops_inspect_files_under_test
    Dir.mktmpdir('lint-probe', File.join(ROOT, 'test')) do |directory|
      path = File.join(directory, 'probe.rb')
      File.write(path, PROBE)
      output, status = lint_file(path, 'Minitest/AssertEmpty')
      refute_predicate status, :success?, output
      assert_includes output, 'Minitest/AssertEmpty'
    end
  end

  private

  def show_cops(cop)
    Bundler.with_unbundled_env do
      Open3.capture2e(
        { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile') },
        'bundle', 'exec', 'rubocop', '--show-cops', cop,
        chdir: ROOT
      )
    end
  end

  def lint_file(path, cop)
    Bundler.with_unbundled_env do
      Open3.capture2e(
        { 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile') },
        'bundle', 'exec', 'rubocop', '--only', cop, path,
        chdir: ROOT
      )
    end
  end
end
