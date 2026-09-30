# frozen_string_literal: true

require_relative 'install_support'

class InstallVersionTest < Minitest::Test
  include InstallTestSupport

  def test_missing_version_refuses_installation
    File.unlink(File.join(@source, 'lib/shaka/version.rb'))

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Missing Shaka version'
    refute_path_exists @destination
  end

  def test_unparseable_version_refuses_installation
    File.write(File.join(@source, 'lib/shaka/version.rb'), 'module Shaka; END; end')

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Missing Shaka version'
    refute_path_exists @destination
  end

  def test_version_declared_in_another_module_refuses_installation
    File.write(File.join(@source, 'lib/shaka/version.rb'), "module Other\n  VERSION = '0.1.0'\nend\n")

    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Missing Shaka version'
    refute_path_exists @destination
  end

  def test_non_string_version_refuses_installation_without_a_stack_trace
    %w[1 nil].each do |value|
      File.write(File.join(@source, 'lib/shaka/version.rb'), "module Shaka; VERSION = #{value}; end\n")

      output, status = install
      refute_predicate status, :success?
      assert_includes output, 'Missing Shaka version'
      refute_includes output, 'Traceback'
      refute_path_exists @destination
    end
  end

  def test_interpolated_version_refuses_installation
    File.write(File.join(@source, 'lib/shaka/version.rb'), <<~RUBY)
      module Shaka
        SUFFIX = '.0'
        VERSION = "1\#{SUFFIX}"
      end
    RUBY

    assert_missing_version
  end

  def test_duplicate_version_assignments_refuse_installation
    File.write(File.join(@source, 'lib/shaka/version.rb'), <<~RUBY)
      module Shaka
        VERSION = '0.1.0.pre.1'
        VERSION = '0.2.0.pre.1'
      end
    RUBY

    assert_missing_version
  end

  def test_reopened_shaka_module_with_second_version_refuses_installation
    File.write(File.join(@source, 'lib/shaka/version.rb'), <<~RUBY)
      module Shaka
        VERSION = '0.1.0.pre.1'
      end
      module Shaka
        VERSION = '0.2.0.pre.1'
      end
    RUBY

    assert_missing_version
  end

  def test_qualified_second_version_refuses_installation
    File.write(File.join(@source, 'lib/shaka/version.rb'), <<~RUBY)
      module Shaka
        VERSION = '0.1.0.pre.1'
      end
      Shaka::VERSION = '0.2.0.pre.1'
    RUBY

    assert_missing_version
  end

  private

  def assert_missing_version
    output, status = install
    refute_predicate status, :success?
    assert_includes output, 'Missing Shaka version'
    refute_path_exists @destination
  end
end
