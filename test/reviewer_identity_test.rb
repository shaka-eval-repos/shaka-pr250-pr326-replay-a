# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/reviewer_selection'

# Parsing the PROVIDER/MODEL_FAMILY identities the command accepts.
class ReviewerIdentityTest < Minitest::Test
  # split('/') drops trailing empties, so a stray slash would have validated.
  def test_rejects_an_identity_with_a_stray_slash
    ['openai/gpt/', 'openai/', '/gpt'].each do |text|
      error = assert_raises(Shaka::Error) { Shaka::ReviewerSelection.parse(text) }

      assert_includes error.message, 'PROVIDER/MODEL_FAMILY'
    end
  end

  def test_rejects_an_identity_without_a_model_family
    error = assert_raises(Shaka::Error) { Shaka::ReviewerSelection.parse('anthropic') }

    assert_includes error.message, 'PROVIDER/MODEL_FAMILY'
  end

  def test_accepts_a_well_formed_identity
    assert_equal({ 'provider' => 'openai', 'model_family' => 'codex' },
                 Shaka::ReviewerSelection.parse('openai/codex'))
  end

  def test_rejects_an_identity_with_embedded_control_whitespace
    ["openai/co\ndex", "openai/co\rdex", "openai/co\tdex"].each do |text|
      error = assert_raises(Shaka::Error) { Shaka::ReviewerSelection.parse(text) }

      assert_includes error.message, 'PROVIDER/MODEL_FAMILY'
    end
  end
end
