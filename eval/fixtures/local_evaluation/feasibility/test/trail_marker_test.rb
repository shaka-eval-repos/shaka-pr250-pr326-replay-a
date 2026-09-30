require 'minitest/autorun'
require_relative '../lib/trail_marker'

class TrailMarkerTest < Minitest::Test
  def test_estimates_segment_time
    assert_equal '6.0.6', Gem.loaded_specs.fetch('minitest').version.to_s
    assert_equal 42, TrailMarker.minutes(3.5, 12)
    assert_raises(ArgumentError) { TrailMarker.minutes(-1, 12) }
    assert_raises(ArgumentError) { TrailMarker.minutes(1, 0) }
  end
end
