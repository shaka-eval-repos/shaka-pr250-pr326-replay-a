# frozen_string_literal: true

require_relative 'install_support'
require 'fileutils'
require 'rbconfig'
require 'shellwords'
require 'json'

module InstallTestAssertions
  def assert_skill_link(source, destination, content)
    assert File.symlink?(destination)
    refute_equal File.realpath(source), File.readlink(destination)
    assert_includes File.readlink(destination), '/.local/share/shaka/installs/'
    assert_equal content, File.read(File.join(destination, 'SKILL.md'))
  end
end

class InstallTest < Minitest::Test
  include InstallTestAssertions
  include InstallTestSupport

  def test_installs_into_an_explicit_directory_with_spaces
    output, status = install

    assert_predicate status, :success?, output
    assert_skill_link(@source, @destination, 'version one')
    assert_skill_link(@rct_source, @rct_destination, 'rct version one')
    executable = Shellwords.escape(File.join(@destination, 'scripts/shaka'))
    assert_includes output, "#{executable} seam init --help"
  end

  def test_repeat_install_keeps_the_same_link
    install
    original = File.lstat(@destination).ino
    output, status = install

    assert_predicate status, :success?, output
    assert_equal original, File.lstat(@destination).ino
  end

  def test_default_install_remains_portable_shaka_only
    output, status = run_installer('--skills-dir', @skills_dir)

    assert_predicate status, :success?, output
    assert_skill_link(@source, @destination, 'version one')
    refute_path_exists @rct_destination
  end

  def test_refuses_a_foreign_directory_and_preserves_its_contents
    FileUtils.mkdir_p(@destination)
    marker = File.join(@destination, 'keep')
    File.write(marker, 'user content')

    refute_predicate install.last, :success?
    assert_equal 'user content', File.read(marker)
  end

  def test_refuses_an_existing_file
    FileUtils.mkdir_p(@skills_dir)
    File.write(@destination, 'user file')

    refute_predicate install.last, :success?
    assert_equal 'user file', File.read(@destination)
  end

  def test_refuses_a_foreign_symlink
    foreign = File.join(@directory, 'foreign')
    FileUtils.mkdir_p([foreign, @skills_dir])
    File.symlink(foreign, @destination)

    refute_predicate install.last, :success?
    assert_equal foreign, File.readlink(@destination)
    assert File.directory?(foreign)
  end

  def test_refuses_a_broken_symlink
    FileUtils.mkdir_p(@skills_dir)
    missing = File.join(@directory, 'missing')
    File.symlink(missing, @destination)

    refute_predicate install.last, :success?
    assert_equal missing, File.readlink(@destination)
    refute_path_exists missing
  end

  def test_rejects_invalid_arguments_without_installing
    [[], ['--skills-dir'], ['--skills-dir', ''], ['--unknown'],
     ['--skills-dir', @skills_dir, 'extra']].each do |arguments|
      _output, status = run_installer(*arguments)
      refute_predicate status, :success?, arguments.inspect
      refute_path_exists @skills_dir
    end
  end

  def test_source_upgrade_is_visible_without_reinstalling
    install
    File.write(File.join(@source, 'SKILL.md'), 'version two')

    assert_equal 'version one', File.read(File.join(@destination, 'SKILL.md'))
  end

  def test_preflights_every_skill_before_installing_any_link
    FileUtils.mkdir_p(@rct_destination)
    marker = File.join(@rct_destination, 'keep')
    File.write(marker, 'user content')

    refute_predicate install.last, :success?
    refute_path_exists @destination
    assert_equal 'user content', File.read(marker)
  end
end
