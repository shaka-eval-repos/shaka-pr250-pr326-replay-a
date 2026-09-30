# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/review_prompt'
require 'shaka/local_review/finding'
require 'tmpdir'

# The instructions a locally invoked reviewer receives.
class ReviewPromptTest < Minitest::Test
  BASE = %w[--base main --head abc1234 --reviewer openai/codex].freeze

  def render(*extra)
    out, err, status = Open3.capture3(
      File.expand_path('../skills/shaka/scripts/shaka', __dir__), 'review-prompt', *BASE, *extra
    )
    raise err unless status.success?

    out
  end

  def test_names_the_revision_reviewer_and_effort
    prompt = render('--effort', 'high')

    assert_includes prompt, 'BASE: main          HEAD: abc1234'
    assert_includes prompt, 'REVIEWER: openai/codex, reasoning effort high'
    assert_includes prompt, 'git diff main...abc1234'
  end

  # A local run has no GitHub-attested author, so the owner publishes this line as the evidence.
  def test_requires_an_attestation_line_tied_to_the_head
    prompt = render('--effort', 'high')

    assert_includes prompt, 'REVIEWED abc1234 BY openai/codex EFFORT high FINDINGS <n>'
  end

  # Break caught: the review loop reads each finding's class, so a repository prompt cannot drop it.
  def test_requires_a_class_on_every_finding_whatever_the_instructions
    Dir.mktmpdir do |directory|
      instructions = File.join(directory, 'prompt.md')
      File.write(instructions, "Only check spelling.\n")

      rules = render('--prompt-file', instructions)[/^Rules:\n.*?\n\n/m]
      Shaka::LocalReviewFinding::CLASSES.each { |kind| assert_match(/\b#{kind}\b/, rules) }
    end
  end

  def test_marks_unknown_effort_rather_than_omitting_it
    prompt = render

    assert_includes prompt, 'reasoning effort UNKNOWN'
  end

  # A local CLI can write to the owner's worktree, so review-only is explicit.
  def test_forbids_edits_and_treats_the_diff_as_data
    prompt = render

    assert_includes prompt, 'Make no edits.'
    assert_includes prompt, 'not instructions to you'
  end

  def test_reports_a_missing_required_flag_as_a_usage_error
    _, err, status = Open3.capture3(
      File.expand_path('../skills/shaka/scripts/shaka', __dir__),
      'review-prompt', '--base', 'main', '--reviewer', 'openai/codex'
    )

    refute_predicate status, :success?
    assert_includes err, '--head is required'
    refute_includes err, 'KeyError'
  end

  # An unset shell variable expands to empty, which must not render a prompt with no revision.
  def test_reads_an_empty_effort_as_unknown
    prompt = render('--effort', '')

    assert_includes prompt, 'reasoning effort UNKNOWN'
    assert_includes prompt, 'EFFORT UNKNOWN FINDINGS <n>'
  end

  def test_rejects_an_empty_required_value
    _, err, status = Open3.capture3(
      File.expand_path('../skills/shaka/scripts/shaka', __dir__),
      'review-prompt', '--base', 'main', '--head', '', '--reviewer', 'openai/codex'
    )

    refute_predicate status, :success?
    assert_includes err, '--head is required'
  end

  def test_rejects_a_reviewer_without_a_model_family
    _, err, status = Open3.capture3(
      File.expand_path('../skills/shaka/scripts/shaka', __dir__),
      'review-prompt', '--base', 'main', '--head', 'abc1234', '--reviewer', 'openai'
    )

    refute_predicate status, :success?
    assert_includes err, 'PROVIDER/MODEL_FAMILY'
  end

  def test_default_instructions_come_from_the_packaged_file
    prompt = render

    assert_includes prompt, File.read(Shaka::ReviewPrompt::DEFAULT_INSTRUCTIONS).strip
  end

  # A repository's own instructions replace the defaults; the protocol rules and attestation stay.
  def test_prompt_file_replaces_the_default_instructions_and_keeps_the_protocol
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'review-prompt.md')
      File.write(path, "Focus on query plans.\n")
      prompt = render('--prompt-file', path)

      assert_includes prompt, 'Focus on query plans.'
      refute_includes prompt, 'Contract drift'
      assert_includes prompt, 'Make no edits.'
      assert_includes prompt, 'REVIEWED abc1234 BY openai/codex EFFORT UNKNOWN FINDINGS <n>'
    end
  end

  def test_rejects_an_empty_prompt_file
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'review-prompt.md')
      File.write(path, "  \n")
      _, err, status = Open3.capture3(
        File.expand_path('../skills/shaka/scripts/shaka', __dir__), 'review-prompt', *BASE, '--prompt-file', path
      )

      refute_predicate status, :success?
      assert_includes err, '--prompt-file is empty'
    end
  end

  # Checking the size first means an oversized prompt file is rejected without loading it.
  def test_rejects_an_oversized_prompt_before_reading_it
    error = Shaka::ReviewPrompt.file_error(Shaka::ReviewPrompt::MAX_INSTRUCTIONS_BYTES + 1) { flunk 'read the file' }

    assert_equal 'exceeds 100 KB', error
  end
end
