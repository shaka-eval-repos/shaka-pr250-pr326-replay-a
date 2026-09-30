# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'opening_check_test_helpers'
require_relative '../skills/shaka/lib/shaka/opening_check'

class OpeningInterpreterGuardTest < Minitest::Test
  include OpeningCheckTestHelpers

  def test_candidate_backed_interpreter_skips_external_reviewer
    with_claude(parse('shaka merge', false)) do |root, trace, bin|
      interpreter_trace = File.join(File.dirname(root), 'node-called')
      add_candidate_interpreter(root, bin, interpreter_trace)
      result = check('`shaka merge` checks the head.', root:)
      assert_equal 'not_checked', result.fetch('status')
      refute_path_exists trace
      refute_path_exists interpreter_trace
    end
  end

  private

  def add_candidate_interpreter(root, bin, trace)
    target = File.join(root, 'node')
    File.write(target, "#!/bin/sh\ntouch #{trace}\nexit 1\n")
    File.chmod(0o755, target)
    File.symlink(target, File.join(bin, 'node'))
    claude = File.join(bin, 'claude')
    File.write(claude, File.read(claude).sub(/\A#![^\n]+/, '#!/usr/bin/env node'))
  end
end
