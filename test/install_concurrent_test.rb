# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'
require 'shaka/install/source'
require 'shaka/install/package'

class InstallConcurrentTest < Minitest::Test
  include InstallTestSupport

  def test_reuses_valid_package_published_during_staging
    package, root = fixture_package
    target = with_publish_race { package.prepare(root) }
    assert_equal target, package.verify(target)
  end

  private

  def fixture_package
    root = File.join(@directory, 'source')
    tree = Shaka::Install::Tree.new(['shaka'])
    source = Shaka::Install::Source.new(root, ['shaka'], tree)
    package = Shaka::Install::Package.new(File.join(@directory, 'managed'), source, ['shaka'], tree)
    [package, root]
  end

  def with_publish_race
    concurrent_publish = lambda do |staging, target|
      FileUtils.cp_r(staging, target)
      raise Errno::EEXIST
    end

    original_rename = File.method(:rename)
    File.define_singleton_method(:rename, &concurrent_publish)
    yield
  ensure
    File.define_singleton_method(:rename, original_rename) if original_rename
  end
end
