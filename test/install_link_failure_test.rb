# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/links'
require 'shaka/installer'

class InstallLinkFailureTest < Minitest::Test
  include InstallTestSupport

  def test_failed_second_link_restores_the_first
    output, status = install
    assert_predicate status, :success?, output
    original = File.readlink(@destination)

    capture_io { assert_raises(Errno::EACCES) { failing_linker.switch_all(replacement_package) } }
    assert_equal original, File.readlink(@destination)
  end

  def test_failed_second_link_removes_new_first_link
    linker = failing_linker_class.new(@skills_dir, File.join(@directory, 'managed'),
                                      File.realpath(File.join(@directory, 'source')), %w[shaka rct])

    capture_io { assert_raises(Errno::EACCES) { linker.switch_all(replacement_package) } }
    refute File.symlink?(@destination)
    refute File.symlink?(@rct_destination)
  end

  def test_output_failure_restores_the_link_just_switched
    output, status = install
    assert_predicate status, :success?, output
    original = File.readlink(@destination)

    assert_raises(Errno::EPIPE) { output_failure_linker.switch_all(replacement_package) }
    assert_equal original, File.readlink(@destination)
  end

  def test_closed_output_stream_restores_the_link_just_switched
    output, status = install
    assert_predicate status, :success?, output
    original = File.readlink(@destination)

    assert_raises(IOError) { output_failure_linker(IOError).switch_all(replacement_package) }
    assert_equal original, File.readlink(@destination)
  end

  def test_post_switch_output_failure_does_not_report_a_failed_install
    installer = Class.new(Shaka::Installer) do
      def puts(*) = raise IOError
    end
    source = File.join(@directory, 'source')
    subject = installer.new(source_root: source, skills_dir: @skills_dir, names: %w[shaka rct],
                            managed_dir: File.join(@directory, 'managed'))

    capture_io { subject.run }
    assert_equal 'version one', File.read(File.join(@destination, 'SKILL.md'))
    assert_equal 'rct version one', File.read(File.join(@rct_destination, 'SKILL.md'))
  end

  private

  def failing_linker
    failing_linker_class.new(@skills_dir, File.dirname(package_path), File.realpath(File.join(@directory, 'source')),
                             %w[shaka rct])
  end

  def failing_linker_class
    Class.new(Shaka::Install::Links) do
      private

      def switch_one(name, target)
        raise Errno::EACCES if name == 'rct'

        super
      end
    end
  end

  def output_failure_linker(error = Errno::EPIPE)
    klass = Class.new(Shaka::Install::Links) do
      private

      define_method(:puts) { |*| raise error }
    end
    klass.new(@skills_dir, File.dirname(package_path), File.realpath(File.join(@directory, 'source')),
              %w[shaka rct])
  end

  def replacement_package
    target = File.join(@directory, 'replacement')
    %w[shaka rct].each { |name| FileUtils.mkdir_p(File.join(target, 'skills', name)) }
    target
  end
end
