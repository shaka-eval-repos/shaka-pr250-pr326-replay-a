# frozen_string_literal: true

require_relative 'install_support'

# A project's Ruby and Bundler settings must not decide whether Shaka starts.
class RubyLauncherTest < Minitest::Test
  include InstallTestSupport

  SOURCE_HELPER = File.expand_path('../skills/shaka/scripts/shaka', __dir__)
  OLD_RUBY = 'Object.send(:remove_const, :RUBY_VERSION); RUBY_VERSION = "3.3.7"; load ARGV.shift'

  def test_installed_helper_ignores_the_project_ruby_and_bundler
    install_full_skill
    output, status = Open3.capture2e(project_environment, File.join(@destination, 'scripts', 'shaka'), '--help',
                                     chdir: project)
    assert_predicate status, :success?, output
    assert_includes output, 'Usage: shaka'
  end

  def test_installer_records_the_ruby_that_ran_it
    install_full_skill
    recorded = File.join(@home, '.local/share/shaka/installs/.shaka-ruby')
    assert_equal "#{File.realpath(RbConfig.ruby)}\n", File.read(recorded)
  end

  def test_shaka_ruby_overrides_the_recorded_ruby
    install_full_skill
    override = fake_ruby('override-ruby', 'echo "override $*"')
    output, status = Open3.capture2e({ 'SHAKA_RUBY' => override }, File.join(@destination, 'scripts', 'shaka'),
                                     'workflow', chdir: project)
    assert_predicate status, :success?, output
    preload = '-r /.+/lib/shaka/ruby_requirement\.rb'
    assert_match(%r{\Aoverride --disable-gems --disable-rubyopt #{preload} /.+/scripts/shaka\.rb workflow$}, output)
  end

  def test_installed_helper_refuses_a_removed_recorded_ruby
    install_full_skill
    File.write(File.join(@home, '.local/share/shaka/installs/.shaka-ruby'), "#{File.join(@directory, 'gone')}\n")
    output, status = Open3.capture2e(project_environment, File.join(@destination, 'scripts', 'shaka'), '--help',
                                     chdir: project)
    refute_predicate status, :success?
    assert_includes output, "(#{File.join(@directory, 'gone')}). Rerun bin/install with Ruby 3.4"
    refute_includes output, 'project ruby ran'
  end

  def test_installed_helper_refuses_a_missing_ruby_record
    install_full_skill
    File.unlink(File.join(@home, '.local/share/shaka/installs/.shaka-ruby'))
    output, status = Open3.capture2e(project_environment, File.join(@destination, 'scripts', 'shaka'), '--help',
                                     chdir: project)
    refute_predicate status, :success?
    assert_includes output, 'Rerun bin/install with Ruby 3.4'
    refute_includes output, 'project ruby ran'
  end

  def test_source_checkout_uses_path_ruby_without_project_ruby_options
    environment = { 'RUBYOPT' => '-rproject_bundler_setup', 'BUNDLE_GEMFILE' => File.join(project, 'Gemfile'),
                    'CDPATH' => '.' }
    # A bare relative path, which Ruby would search for in its load path rather than here.
    output, status = Open3.capture2e(environment, 'skills/shaka/scripts/shaka', '--help',
                                     chdir: File.expand_path('..', __dir__))
    assert_predicate status, :success?, output
    assert_includes output, 'Usage: shaka'
  end

  def test_helper_and_installer_explain_an_old_ruby
    [SOURCE_HELPER.sub(/\z/, '.rb'), File.expand_path('../bin/install', __dir__)].each do |script|
      output, status = Open3.capture2e(RbConfig.ruby, '-W0', '-e', OLD_RUBY, script, '--help', chdir: project)
      refute_predicate status, :success?, output
      assert_includes output, 'Shaka needs Ruby 3.4 or newer; this Ruby is 3.3.7.'
    end
  end

  private

  def install_full_skill
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
  end

  def project
    path = File.join(@directory, 'project')
    FileUtils.mkdir_p(path)
    File.write(File.join(path, '.ruby-version'), "3.3.7\n")
    File.write(File.join(path, 'Gemfile'), "ruby '>= 9.0'\n")
    path
  end

  # The project's Ruby is first on PATH and refuses to run, and its settings load Bundler.
  def project_environment
    bin = File.dirname(fake_ruby('ruby', 'echo "project ruby ran" >&2; exit 1'))
    { 'PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'RUBYOPT' => '-rproject_bundler_setup',
      'BUNDLE_GEMFILE' => File.join(project, 'Gemfile'), 'GEM_HOME' => File.join(project, 'gems') }
  end

  def fake_ruby(name, body)
    path = File.join(@directory, 'fake-bin', name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end
end
