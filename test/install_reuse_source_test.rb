# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'
require 'shaka/install/source'
require 'shaka/install/package'

class InstallReuseSourceTest < Minitest::Test
  include InstallTestSupport

  def test_reused_package_rechecks_source_after_verification
    root = File.join(@directory, 'source')
    tree = Shaka::Install::Tree.new(['shaka'], source_root: root)
    source = Shaka::Install::Source.new(root, ['shaka'], tree)
    managed = File.join(@directory, 'managed')
    Shaka::Install::Package.new(managed, source, ['shaka'], tree).prepare(root)
    skill = File.join(@source, 'SKILL.md')
    package = package_that_changes_source(managed, source, tree, skill)

    error = assert_raises(ArgumentError) { package.prepare(root) }
    assert_includes error.message, 'Source changed during installation'
  end

  private

  def package_that_changes_source(managed, source, tree, skill)
    klass = Class.new(Shaka::Install::Package) do
      define_method(:verify) do |path|
        File.write(skill, 'changed during verification')
        super(path)
      end
    end
    klass.new(managed, source, ['shaka'], tree)
  end
end
