# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/install/tree'

class InstallCheckoutReferenceTest < Minitest::Test
  include InstallTestSupport

  def test_short_checkout_path_does_not_match_a_skill_path
    path = File.join(@source, 'example.md')
    File.write(path, '$HOME/.agents/skills/shaka/scripts/shaka')

    Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
  end

  def test_short_checkout_path_still_detects_absolute_reference
    path = File.join(@source, 'example.md')
    File.write(path, 'Use /shaka/bin/install')

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
    end
  end

  def test_checkout_root_without_trailing_slash_is_detected
    path = File.join(@source, 'example.md')
    File.write(path, "Run `cd /shaka`\n")

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
    end
  end

  def test_checkout_root_followed_by_sentence_punctuation_is_detected
    path = File.join(@source, 'example.md')
    ['Clone to /shaka.', 'Clone to /shaka-'].each do |content|
      File.write(path, content)
      assert_raises(ArgumentError) do
        Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
      end
    end
  end

  def test_checkout_root_prefix_of_another_directory_is_not_detected
    File.write(File.join(@source, 'example.md'), 'Clone to /shaka-next.')

    Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
  end

  def test_file_url_to_checkout_is_detected
    path = File.join(@source, 'example.md')
    File.write(path, 'Open file:///shaka/docs/settings.md')

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
    end
  end

  def test_localhost_file_url_to_checkout_is_detected
    path = File.join(@source, 'example.md')
    File.write(path, 'Open FILE://LOCALHOST/shaka/docs/settings.md')

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/shaka')
    end
  end

  def test_shell_escaped_checkout_path_is_detected
    path = File.join(@source, 'example.md')
    File.write(path, 'Run /Shaka\\ Dev/bin/install')

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/Shaka Dev')
    end
  end

  def test_percent_encoded_file_url_to_checkout_is_detected
    path = File.join(@source, 'example.md')
    File.write(path, 'Open file:///Shaka%20Dev/docs/settings.md')

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/Shaka Dev')
    end
  end

  def test_single_slash_file_url_to_checkout_is_detected
    File.write(File.join(@source, 'example.md'), 'Open file:/Shaka%20Dev/docs/settings.md')

    assert_raises(ArgumentError) do
      Shaka::Install::Tree.new(['shaka']).reject_checkout_references(File.join(@directory, 'source'), '/Shaka Dev')
    end
  end

  def test_symlinked_checkout_alias_is_detected
    alias_root = File.join(@directory, 'checkout-alias')
    File.symlink(File.join(@directory, 'source'), alias_root)
    File.write(File.join(@source, 'example.md'), "Run #{alias_root}/bin/install")

    output, status = Open3.capture2e({ 'HOME' => @home }, RbConfig.ruby, File.join(alias_root, 'bin/install'),
                                     '--skills-dir', @skills_dir)
    refute_predicate status, :success?
    assert_includes output, 'Checkout reference in package'
    refute_path_exists @destination
  end
end
