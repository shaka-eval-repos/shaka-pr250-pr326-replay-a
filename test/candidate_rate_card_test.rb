# frozen_string_literal: true

require_relative 'usage_test'
require 'shaka/usage/rate_card'
require 'fileutils'
require 'yaml'

module CandidateRateCardFixture
  def implementation(root)
    arguments = root ? ['--rate-root', root] : []
    run_report([candidate_context, candidate_usage], *arguments)
  end

  def capture_usage(records, *, env: {})
    Dir.mktmpdir do |directory|
      file = write_records(directory, records, {})
      environment = { 'PI_CODING_AGENT' => nil, 'CODEX_HOME' => directory, 'CODEX_THREAD_ID' => UsageFixture::THREAD,
                      'CLAUDE_CODE_SESSION_ID' => nil, 'CURSOR_CONVERSATION_ID' => nil }
      Open3.capture3(environment.merge(env), UsageFixture::COMMAND, 'usage', '--file', file, '--commit',
                     UsageFixture::COMMIT, '--contribution', 'implementation', *)
    end
  end

  def with_card(extra = {})
    Dir.mktmpdir do |root|
      write_card(root, extra)
      yield root
    end
  end

  def isolated_ruby
    Dir.mktmpdir do |root|
      bindir = File.join(root, 'bin')
      FileUtils.mkdir_p(bindir)
      File.symlink(RbConfig.ruby, File.join(bindir, 'ruby'))
      yield bindir
    end
  end

  def in_empty_directory(&)
    Dir.mktmpdir do |root|
      nested = File.join(root, 'nested')
      FileUtils.mkdir_p(nested)
      Dir.chdir(nested, &)
    end
  end

  def candidate_context = priced_context('current', 'gpt-candidate-only')

  def candidate_usage = priced_usage('priced', 'current', 1_000, cached: 0, output: 0)

  def terra_context = priced_context('current', 'gpt-5.6-terra')

  def terra_usage = priced_usage('priced', 'current', 200_000, cached: 40_000, output: 20_000)

  def rewrite_threshold(root, value)
    path = File.join(root, Shaka::RateCard::PATH)
    File.write(path, File.read(path).sub('threshold: 272000', "threshold: #{value}"))
  end

  def write_card(root, extra)
    path = File.join(root, Shaka::RateCard::PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(candidate_document(extra)))
  end

  def candidate_document(extra)
    { 'openai' => openai_section(extra), 'cursor' => cursor_section, 'anthropic' => anthropic_section }
  end

  def openai_section(extra)
    model = { 'credits' => %w[10 1 20], 'api' => %w[1 0.1 2] }.merge(extra)
    { 'verified' => '2026-09-23', 'threshold' => 272_000, 'models' => { 'gpt-candidate-only' => model } }
  end

  def cursor_section
    { 'verified' => '2026-09-21', 'long_context' => { 'standard' => 2, 'fast' => 3 }, 'models' => {} }
  end

  def anthropic_section
    { 'verified' => '2026-09-23', 'models' => {} }
  end
end

class CandidateRateCardTest < Minitest::Test
  include UsageFixture
  include CandidateRateCardFixture

  def test_implementation_prices_a_model_the_installed_card_lacks
    with_card do |root|
      report = implementation(root)
      assert_metric report, 'Credits estimate', '0.010000'
      assert_metric report, 'USD estimate', '$0.001000'
      assert_includes report, 'Rate card: candidate checkout'
      refute_includes report, 'not invoices'
    end
  end

  def test_implementation_does_not_fall_back_to_the_installed_card
    with_card do |root|
      report = run_report([terra_context, terra_usage], '--rate-root', root)
      assert_metric report, 'USD estimate', 'UNKNOWN'
      assert_includes report, 'Unsupported provider or configured model'
    end
  end

  def test_review_keeps_the_installed_card_when_a_candidate_card_is_present
    with_card do |root|
      report = run_report([terra_context, terra_usage], '--rate-root', root, contribution: 'review')
      assert_metric report, 'Credits estimate', '14.200000'
      assert_metric report, 'USD estimate', '$0.568000'
      assert_includes report, 'Rate card: installed Shaka'
      refute_includes report, 'candidate checkout'
    end
  end

  def test_implementation_discovers_the_card_from_a_subdirectory
    with_card do |root|
      system('git', 'init', '-q', root) || raise('git init failed')
      nested = File.join(root, 'nested')
      FileUtils.mkdir_p(nested)
      report = Dir.chdir(nested) { implementation(nil) }
      assert_metric report, 'USD estimate', '$0.001000'
      assert_includes report, 'Rate card: candidate checkout'
    end
  end

  def test_threshold_note_follows_the_candidate_card
    with_card do |root|
      rewrite_threshold(root, 1_000)
      report = run_report([candidate_context, priced_usage('priced', 'current', 1_001, cached: 0, output: 0)],
                          '--rate-root', root)
      assert_includes report, '1K context threshold'
      refute_includes report, '272K'
    end
  end

  def test_a_candidate_source_url_is_rejected
    with_card('source' => 'https://attacker.example/docs') do |root|
      _output, error, status = capture_usage([candidate_context, candidate_usage], '--rate-root', root)
      refute_predicate status, :success?
      assert_includes error, 'unknown rate-card key: source'
    end
  end

  def test_implementation_discovers_a_checkout_card_the_installed_copy_lacks
    with_card do |root|
      report = Dir.chdir(root) { implementation(nil) }
      assert_metric report, 'USD estimate', '$0.001000'
      assert_includes report, 'Rate card: candidate checkout'
    end
  end

  def test_missing_git_fails_checkout_discovery
    isolated_ruby do |bindir|
      _output, error, status = in_empty_directory do
        capture_usage([candidate_context, candidate_usage], env: { 'PATH' => bindir })
      end
      refute_predicate status, :success?
      assert_includes error, 'Could not read the git checkout'
    end
  end

  def test_a_missing_candidate_card_fails_the_report
    Dir.mktmpdir do |root|
      _output, error, status = capture_usage([candidate_context, candidate_usage], '--rate-root', root)
      refute_predicate status, :success?
      assert_includes error, 'Candidate rate card is missing'
    end
  end

  def test_a_card_the_loader_cannot_check_fails_the_report
    with_card('formula' => 'candidate') do |root|
      output, error, status = capture_usage([candidate_context, candidate_usage], '--rate-root', root)
      refute_predicate status, :success?
      assert_includes error, 'unknown rate-card key: formula'
      assert_empty output
    end
  end
end
