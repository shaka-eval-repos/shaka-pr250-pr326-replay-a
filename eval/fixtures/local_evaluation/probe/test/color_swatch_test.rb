require 'minitest/autorun'
require_relative '../lib/color_swatch'

class ColorSwatchTest < Minitest::Test
  def test_normalizes_a_color_label
    assert_equal '6.0.6', Gem.loaded_specs.fetch('minitest').version.to_s
    assert_equal '#2A6F97', ColorSwatch.label('2a6f97')
    assert_raises(ArgumentError) { ColorSwatch.label('not-a-color') }
    assert_raises(ArgumentError) { ColorSwatch.label('#abc') }
  end
end
