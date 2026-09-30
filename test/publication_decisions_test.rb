# frozen_string_literal: true

require_relative 'publication_test'

class PublicationDecisionsTest < Minitest::Test
  def render(**changes)
    Shaka::Publication.description(
      { 'identity' => PublicationRegressionTest::IDENTITY, 'summary' => 'A summary.',
        'walkthrough' => PublicationRegressionTest::WALKTHROUGH, 'deployment' => 'none',
        'table' => PublicationRegressionTest::TABLE, 'provenance' => PUBLIC_PROVENANCE,
        'usage' => PublicationRegressionTest::USAGE_OBJECT, 'details' => [] }.merge(changes)
    )
  end

  def test_decisions_render_between_the_walkthrough_link_and_other_sections
    rendered = render('decisions' => ['Keep the label?', 'Which base?'],
                      'sections' => [{ 'heading' => 'Outcome', 'body' => 'What landed.' }])
    marker = "<!-- shaka:decisions -->\n## Decisions for the maintainer\n\n- Keep the label?\n- Which base?\n"
    decisions = rendered.index(marker)
    walkthrough = rendered.index('[Code Walkthrough](')
    outcome = rendered.index("## Outcome\n")

    refute_nil decisions
    assert_operator walkthrough, :<, decisions
    assert_operator decisions, :<, outcome
  end

  def test_an_empty_decisions_list_omits_the_section
    refute_includes render('decisions' => []), 'Decisions for the maintainer'
  end

  def test_a_hand_written_decisions_section_is_refused
    error = assert_raises(Shaka::Error) do
      render('sections' => [{ 'heading' => 'Decisions for the maintainer', 'body' => '- One?' }])
    end
    assert_includes error.message, 'decisions list'
  end

  def test_a_blank_decision_is_refused
    error = assert_raises(Shaka::Error) { render('decisions' => ['  ']) }
    assert_includes error.message, 'decision'
  end
end
