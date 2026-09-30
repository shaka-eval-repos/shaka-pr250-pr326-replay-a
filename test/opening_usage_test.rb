# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'opening_check_test_helpers'
require_relative '../skills/shaka/lib/shaka/opening_check'

class OpeningUsageTest < Minitest::Test
  include OpeningCheckTestHelpers

  def test_claude_opening_check_leaves_no_usage_file
    with_claude(parse('Pull requests', true)) do |root, _trace|
      with_tmpdir(File.dirname(root)) do
        assert_equal 'passed', check('Pull requests show the outcome.', root:).fetch('status')
        assert_empty Dir.glob(File.join(Dir.tmpdir, 'shaka-review-usage-*.json'))
      end
    end
  end

  def test_codex_opening_does_not_collect_usage
    with_claude(nil) do |root, _trace, bin|
      output = JSON.generate(parse('Pull requests', true))
      write_fake_codex(bin, output)
      original = Shaka::CodexUsage.method(:announced_session)
      Shaka::CodexUsage.define_singleton_method(:announced_session) { |_| raise 'opening collected usage' }
      assert_equal 'passed', check('Pull requests show the outcome.', root:, reviewer: 'openai/codex').fetch('status')
    ensure
      Shaka::CodexUsage.define_singleton_method(:announced_session, original) if original
    end
  end

  private

  def write_fake_codex(bin, output)
    path = File.join(bin, 'codex')
    File.write(path, "#!#{RbConfig.ruby}\nFile.write(ARGV[ARGV.index('-o') + 1], #{output.inspect})\n")
    File.chmod(0o755, path)
  end

  def with_tmpdir(path)
    original = ENV.fetch('TMPDIR', nil)
    ENV['TMPDIR'] = path
    yield
  ensure
    ENV['TMPDIR'] = original
  end
end
