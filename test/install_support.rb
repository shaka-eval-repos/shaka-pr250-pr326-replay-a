# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'rbconfig'
require 'json'

module InstallTestSupport
  def setup
    prepare_paths
    copy_installer
    write_skills
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def install
    run_installer('--skills-dir', @skills_dir, '--with-rct')
  end

  def run_installer(*)
    Open3.capture2e({ 'HOME' => @home }, RbConfig.ruby, @installer, *)
  end

  def git(*)
    output, status = Open3.capture2e('git', *)
    assert_predicate status, :success?, output
    output
  end

  def package_path
    File.dirname(File.readlink(@destination), 2)
  end

  def package_identity
    JSON.parse(File.read(File.join(package_path, '.shaka-install.json')))
  end

  def unrelated_parent_repository
    git('init', '-q', @directory)
    git('-C', @directory, 'config', 'remote.origin.url', 'https://example.com/unrelated.git')
  end

  private

  def prepare_paths
    @directory = Dir.mktmpdir('workflows-install')
    @source = File.join(@directory, 'source', 'skills', 'shaka')
    @rct_source = File.join(@directory, 'source', 'skills', 'rct')
    @installer = File.join(@directory, 'source', 'bin', 'install')
    @skills_dir = File.join(@directory, 'isolated profile', 'skills')
    @destination = File.join(@skills_dir, 'shaka')
    @rct_destination = File.join(@skills_dir, 'rct')
    @home = File.join(@directory, 'home')
    FileUtils.mkdir_p([@source, @rct_source, File.dirname(@installer)])
  end

  def copy_installer
    FileUtils.cp(File.expand_path('../bin/install', __dir__), @installer)
    library = File.join(@source, 'lib', 'shaka')
    FileUtils.mkdir_p(library)
    FileUtils.cp(File.expand_path('../skills/shaka/lib/shaka/installer.rb', __dir__), library)
    FileUtils.cp(File.expand_path('../skills/shaka/lib/shaka/ruby_requirement.rb', __dir__), library)
    FileUtils.cp_r(File.expand_path('../skills/shaka/lib/shaka/install', __dir__), library)
  end

  def write_skills
    File.write(File.join(@source, 'SKILL.md'), 'version one')
    FileUtils.mkdir_p(File.join(@source, 'scripts'))
    File.write(File.join(@source, 'scripts/shaka'), "#!/usr/bin/env ruby\n")
    File.chmod(0o755, File.join(@source, 'scripts/shaka'))
    File.write(File.join(@source, 'lib/shaka/version.rb'), "module Shaka\n  VERSION = '0.1.0.pre.1'\nend\n")
    File.write(File.join(@rct_source, 'SKILL.md'), 'rct version one')
  end

  def replace_fixture_with_full_skill
    root = File.join(@directory, 'source')
    FileUtils.rm_rf(root)
    FileUtils.mkdir_p([File.dirname(@installer), File.dirname(@source)])
    FileUtils.cp(File.expand_path('../bin/install', __dir__), @installer)
    FileUtils.cp_r(File.expand_path('../skills/shaka', __dir__), @source)
  end

  def assert_no_package_symlinks
    links = Dir.glob('**/*', base: package_path).select { |entry| File.symlink?(File.join(package_path, entry)) }
    assert_empty links
  end

  def assert_installed_doctor_works_from_second_worktree
    second_worktree = File.join(@directory, 'worktree-b')
    FileUtils.mkdir_p(second_worktree)
    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor',
                                     '--installation-json', chdir: second_worktree)
    assert_predicate status, :success?, output
    identity = JSON.parse(output)
    assert_equal 'development', identity.fetch('source').fetch('kind')
    assert_equal '0.1.0.pre.1', identity.fetch('version')
    report, = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor', chdir: second_worktree)
    assert_includes report, "installation #{identity.fetch('version')} · development base UNKNOWN content"
  end
end
