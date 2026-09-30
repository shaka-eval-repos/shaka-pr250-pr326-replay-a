# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/version'

class VersionTest < Minitest::Test
  def test_product_stage_is_early_0_0_x_and_independent_of_the_gem_identifier
    assert_equal '0.0.x', Shaka::PRODUCT_STAGE
    refute_equal Shaka::PRODUCT_STAGE, Shaka::VERSION
  end

  def test_registry_stays_on_the_published_0_1_0_prerelease_line
    version = Gem::Version.new(Shaka::VERSION)

    assert_predicate version, :prerelease?
    assert_match(/\A0\.1\.0\.pre\.\d+\z/, version.to_s)
    assert_equal [0, 1, 0], version.segments.take(3)
    assert_operator version, :>, Gem::Version.new('0.0.999')
    refute_operator Gem::Version.new('0.0.1'), :>=, version
  end
end
