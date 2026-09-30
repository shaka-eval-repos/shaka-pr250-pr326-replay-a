# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'

class InstallFileUriNormalizationTest < Minitest::Test
  include InstallTestSupport

  def test_file_uri_dot_segments_do_not_hide_checkout_reference
    root = File.join(@directory, 'source')
    path = File.join(@source, 'example.md')
    [['/tmp/shaka', 'file:///tmp/./shaka/docs/settings.md'],
     ['/tmp/shaka', 'file:///tmp/%2E/shaka/docs/settings.md'],
     ['/shaka', 'file:///tmp/../shaka/docs/settings.md']].each do |checkout, url|
      File.write(path, "Open #{url}")

      assert_raises(ArgumentError) do
        Shaka::Install::Tree.new(['shaka']).reject_checkout_references(root, checkout)
      end
    end
  end
end
