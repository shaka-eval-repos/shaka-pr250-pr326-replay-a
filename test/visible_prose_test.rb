# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/visible_prose'

# Only prose GitHub shows without expanding anything counts, split where sentences end.
class VisibleProseTest < Minitest::Test
  # GitHub's own rendering of test/fixtures/prose/rendered.md.
  RENDERED = File.read(File.expand_path('fixtures/prose/rendered.html', __dir__), encoding: 'UTF-8')

  def test_only_prose_github_shows_is_measured
    expected = [['🤖 Claude Code · Anthropic · claude-opus-5-5 · xhigh'],
                ['The summary uses Code in code.', 'Reviewers see the code.', 'iOS builds pass.'],
                ['Code Walkthrough'], ['Example:'], ['Item one'], ['Nested item'], ['Item two with a link'],
                ['Usage'], ['After details.']]

    assert_equal expected, paragraphs(RENDERED)
  end

  def test_a_list_item_is_measured_whole_and_sentences_end_after_any_quote
    html = '<ul><li><p>“First part.” Then… More.</p><p>✅ Second part.</p></li><li>Next item.</li></ul>'

    assert_equal [['“First part.', 'Then…', 'More.', '✅ Second part.'], ['Next item.']], paragraphs(html)
  end

  def test_nonbreaking_spaces_separate_words_and_inline_tags_do_not
    html = "<p>One&nbsp;two&#160;three\u00A0four re<strong>try</strong>.</p>"

    assert_equal 5, Shaka::VisibleProse.words(paragraphs(html).flatten.join(' '))
  end

  def test_a_code_span_keeps_the_punctuation_that_ends_its_sentence
    html = '<p>Call <code>empty?</code> Then stop at <code>done.</code> Wait <code>pending…</code> Next.</p>'

    assert_equal [['Call Code?', 'Then stop at Code.', 'Wait Code…', 'Next.']], paragraphs(html)
  end

  def test_a_hard_line_break_keeps_its_sentence_together
    assert_equal [['First half second half.']], paragraphs("<p>First half<br>\nsecond half.</p>")
  end

  def test_open_details_and_collapsed_summaries_are_visible
    html = '<details open><summary>Why</summary><p>Shown.</p></details>' \
           '<details><summary>Usage</summary><p>Hidden.</p></details>'

    assert_equal [['Why'], ['Shown.'], ['Usage']], paragraphs(html)
  end

  def test_an_unclosed_hidden_block_hides_only_what_github_hides
    html = "<p>Before.</p>\n<details>\n<p>Inside.</p>"

    assert_equal [['Before.']], paragraphs(html)
  end

  private

  def paragraphs(html) = Shaka::VisibleProse.new(html).paragraphs
end
