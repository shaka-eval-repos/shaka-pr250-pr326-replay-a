# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../skills/shaka/lib/shaka/recommendation'

class RecommendationTest < Minitest::Test
  CONTENT = {
    'value' => 'Reviewers cannot tell whether agent-proposed work was worth doing; a guide note was cheaper.',
    'scope' => 'One instruction and one behavior test.',
    'risk' => 'Changes agent selection policy.',
    'model' => 'gpt-example',
    'effort' => 'medium',
    'reason' => 'The policy change needs careful reasoning.'
  }.freeze

  def test_renders_assessment_before_the_result
    rendered = Shaka::Recommendation.new(CONTENT).render
    CONTENT.each_value { |value| assert_includes rendered, value }

    locations = CONTENT.values.map { |value| rendered.index(value) }
    assert_equal locations.sort, locations
  end

  def test_requires_each_part_instead_of_supplying_a_default
    CONTENT.each_key do |field|
      error = assert_raises(Shaka::Error) { Shaka::Recommendation.new(CONTENT.reject { |key| key == field }).render }
      assert_includes error.message, field
    end
  end

  # The value line is what a reader checks against the diff, so it leads the
  # assessment: why this work at all, before how large and how risky it is.
  def test_value_leads_the_assessment
    rendered = Shaka::Recommendation.new(CONTENT).render

    assert_equal "Value: #{CONTENT.fetch('value')}", rendered.lines.first.chomp
  end

  # A blank or multi-line value lets a paragraph of justification stand in for the
  # one checkable line, which is the whole point of requiring the field.
  def test_value_refuses_blank_and_multi_line_text
    ['', '   ', "Fixes a real problem.\nA doc note was cheaper."].each do |text|
      error = assert_raises(Shaka::Error) { Shaka::Recommendation.new(CONTENT.merge('value' => text)).render }

      assert_includes error.message, 'value'
    end
  end
end
