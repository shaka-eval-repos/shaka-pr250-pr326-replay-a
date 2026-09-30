# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'doctor_command_helper'

# Output goes straight into UTF-8 messages, so bytes a command emits must never be able to
# raise there and take down the report.
class DoctorCommandEncodingTest < Minitest::Test
  include DoctorCommandHelper

  # A localized error message would otherwise reach a UTF-8 interpolation as binary and raise.
  def test_non_ascii_output_comes_back_usable_in_a_message
    out, _error, ok = run_bounded(10, ['ruby', '-e', 'print "caf\u00e9"'])

    assert ok
    assert_equal Encoding::UTF_8, out.encoding
    assert_equal 'café', out
    assert_equal 'saw café', "saw #{out}"
  end

  def test_invalid_bytes_cannot_break_a_message
    out, _error, ok = run_bounded(10, ['ruby', '-e', 'STDOUT.binmode; print "bad\xFFbyte"'])

    assert ok
    assert_predicate out, :valid_encoding?
    assert_kind_of String, "saw #{out}"
  end
end
