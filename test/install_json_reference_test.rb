# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'

class InstallJsonReferenceTest < Minitest::Test
  include InstallTestSupport

  def test_json_escaped_checkout_path_is_rejected
    root = File.join(@directory, 'source')
    content = '{"guide":"\\/tmp\\/shaka\\/docs\\/settings.md"}'
    assert_equal '/tmp/shaka/docs/settings.md', JSON.parse(content).fetch('guide')
    File.write(File.join(@source, 'config.json'), content)

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(root, '/tmp/shaka')
    end
  end

  def test_json_unicode_escaped_checkout_path_is_rejected
    root = File.join(@directory, 'source')
    content = '{"guide":{"path":"\\u002ftmp\\u002Fshaka\\u002fdocs/settings.md"}}'
    assert_equal '/tmp/shaka/docs/settings.md', JSON.parse(content).fetch('guide').fetch('path')
    File.write(File.join(@source, 'config.json'), content)

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(root, '/tmp/shaka')
    end
  end

  def test_json_escaped_similar_path_is_allowed
    root = File.join(@directory, 'source')
    File.write(File.join(@source, 'config.json'), '{"guide":"\\u002ftmp\\u002fshaka-old/docs/settings.md"}')

    Shaka::Install::Tree.new(['shaka']).reject_checkout_references(root, '/tmp/shaka')
  end
end
