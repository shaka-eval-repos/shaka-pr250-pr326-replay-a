# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/repo_prefix'

class RepoPrefixTest < Minitest::Test
  def test_fallback_uses_initials_for_multi_segment_names
    assert_equal 'AW', Shaka::RepoPrefix.fallback('agent-workflows')
    assert_equal 'ROR', Shaka::RepoPrefix.fallback('react_on_rails')
    assert_equal '3T', Shaka::RepoPrefix.fallback('3d-tiles')
  end

  def test_fallback_uses_up_to_four_characters_for_a_single_segment
    assert_equal 'SHAK', Shaka::RepoPrefix.fallback('shakapacker')
    assert_equal 'GO', Shaka::RepoPrefix.fallback('go')
    assert_equal 'WEB3', Shaka::RepoPrefix.fallback('web3')
  end

  def test_fallback_keeps_only_letters_and_digits
    assert_equal 'D3JS', Shaka::RepoPrefix.fallback('d3.js')
    assert_equal 'VUEJ', Shaka::RepoPrefix.fallback('vue.js')
    assert_match Shaka::RepoPrefix::PATTERN, Shaka::RepoPrefix.fallback('d3.js')
  end

  def test_display_uses_a_valid_configured_prefix
    assert_equal({ 'prefix' => 'CPF', 'source' => 'seam' },
                 Shaka::RepoPrefix.display(configured: 'CPF', repository_name: 'control-plane-flow'))
  end

  def test_display_falls_back_when_the_seam_omits_the_prefix
    assert_equal({ 'prefix' => 'SHAK', 'source' => 'fallback' },
                 Shaka::RepoPrefix.display(configured: nil, repository_name: 'shaka'))
  end

  def test_display_refuses_an_invalid_configured_prefix_instead_of_falling_back
    error = assert_raises(Shaka::Error) do
      Shaka::RepoPrefix.display(configured: 'cpf', repository_name: 'control-plane-flow')
    end

    assert_includes error.message, 'repo_prefix'
    refute_includes error.message.downcase, 'fallback'
  end
end
