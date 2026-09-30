# frozen_string_literal: true

require_relative 'review_prompt_file_test'

# A reviewer's model and effort, read from the trusted commit's reviewer list.
module ReviewAgentSettingsFixture
  include ReviewPromptFileFixture

  private

  def codex_agent(settings)
    { 'local_review_agents' => [{ 'provider' => 'openai', 'model_family' => 'codex' }.merge(settings)] }
  end

  # Echoes the requested effort into the attestation and records the arguments it received.
  def fake_codex(bin, head)
    write_executable(bin, 'codex', <<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      File.write(ENV.fetch('REVIEW_TRACE'), JSON.generate({ args: ARGV, prompt: STDIN.read }))
      setting = ARGV.find { |arg| arg.start_with?('model_reasoning_effort=') }
      effort = setting ? setting[/"(.*)"/, 1] : 'UNKNOWN'
      File.write(ARGV.fetch(ARGV.index('-o') + 1),
                 "no findings\\nREVIEWED #{head} BY openai/codex EFFORT \#{effort} FINDINGS 0\\n")
    RUBY
  end

  def codex_arguments(root, base, head, bin, *options)
    output, error, status = run_review(root, base, head, bin, *options)
    assert_predicate status, :success?, "#{output}\n#{error}"
    result = JSON.parse(output)
    File.unlink(result.fetch('report'))
    [JSON.parse(File.read(File.join(root, 'trace.json'))).fetch('args'), result]
  end
end

class ReviewAgentSettingsTest < Minitest::Test
  include ReviewAgentSettingsFixture

  # Break caught: a configured reviewer model is ignored and the CLI's own default runs.
  def test_trusted_model_and_effort_reach_the_reviewer
    with_repository(codex_agent('model' => 'gpt-6-sol', 'effort' => 'medium')) do |root, base, head, bin|
      args, result = codex_arguments(root, base, head, bin)

      assert_equal 'gpt-6-sol', args.fetch(args.index('-m') + 1)
      assert_includes args, 'model_reasoning_effort="medium"'
      assert_equal 'gpt-6-sol', result.fetch('requested_model')
    end
  end

  # A task's explicit choice outranks the repository default.
  def test_explicit_options_override_the_trusted_settings
    with_repository(codex_agent('model' => 'gpt-6-sol', 'effort' => 'medium')) do |root, base, head, bin|
      args, = codex_arguments(root, base, head, bin, '--model', 'gpt-6-astra', '--effort', 'high')

      assert_equal 'gpt-6-astra', args.fetch(args.index('-m') + 1)
      assert_includes args, 'model_reasoning_effort="high"'
    end
  end

  # Break caught: a number in the trusted settings crashes the runner instead of reporting setup failure.
  def test_a_non_text_trusted_setting_is_a_setup_failure
    with_repository(codex_agent('effort' => 3)) do |root, base, head, bin|
      output, _error, status = run_review(root, base, head, bin)
      refute_predicate status, :success?
      result = JSON.parse(output)

      assert_equal 'setup_failure', result.fetch('failure_stage')
      assert_includes result.fetch('reason'), 'effort must be a level name'
    end
  end

  # Break caught: a trusted model with a space reaches the CLI instead of failing as setup.
  def test_a_spaced_trusted_model_is_a_setup_failure
    with_repository(codex_agent('model' => 'gpt 6')) do |root, base, head, bin|
      output, _error, status = run_review(root, base, head, bin)
      refute_predicate status, :success?
      result = JSON.parse(output)

      assert_equal 'setup_failure', result.fetch('failure_stage')
      assert_includes result.fetch('reason'), 'model must not contain whitespace'
    end
  end

  # Break caught: a malformed default blocks the explicit choice that should replace it.
  def test_an_explicit_option_replaces_a_malformed_default
    with_repository(codex_agent('effort' => 3)) do |root, base, head, bin|
      args, = codex_arguments(root, base, head, bin, '--effort', 'medium')

      assert_includes args, 'model_reasoning_effort="medium"'
    end
  end

  # Break caught: a PR picks the model that reviews it by editing its own seam.
  def test_candidate_settings_do_not_choose_the_reviewer_model
    with_repository do |root, base, _head, bin|
      File.write(File.join(root, '.agents/agent-workflow.yml'),
                 YAML.dump(seam(codex_agent('model' => 'candidate-model'))))
      commit!(root, 'candidate settings')
      head = git!(root, 'rev-parse', 'HEAD').strip
      fake_codex(bin, head)
      args, = codex_arguments(root, base, head, bin)

      refute_includes args, 'candidate-model'
      refute_includes args, '-m'
    end
  end
end

class ReviewAgentSettingsSchemaTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_loads_a_reviewer_model_and_effort
    agents = [reviewers.first.merge('model' => 'gpt-6-sol', 'effort' => 'medium'), reviewers.last]
    with_repository('review' => review_policy('local_review_agents' => agents)) do |root|
      entry = Shaka::RepositoryConfig.load(root:).review.fetch('local_review_agents').first

      assert_equal %w[gpt-6-sol medium], entry.values_at('model', 'effort')
    end
  end

  # The effort becomes Codex configuration text and part of the review attestation.
  def test_rejects_an_effort_that_is_not_a_level_name
    assert_agent_error({ 'effort' => 'high" sandbox_mode="danger-full-access' },
                       'review.local_review_agents[0].effort must be a level name')
  end

  def test_rejects_a_blank_or_spaced_model
    assert_agent_error({ 'model' => ' ' }, 'review.local_review_agents[0].model must be a non-empty string')
    assert_agent_error({ 'model' => 'gpt 6' }, 'review.local_review_agents[0].model must not contain whitespace')
  end

  private

  def assert_agent_error(settings, message)
    agents = [reviewers.first.merge(settings)]
    with_repository('review' => review_policy('local_review_agents' => agents)) do |root|
      error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }

      assert_includes error.message, message
    end
  end
end

# Upgrading a seam keeps each reviewer's model and effort.
class ReviewAgentSettingsMigrationTest < Minitest::Test
  def test_migration_retains_reviewer_settings
    agent = { 'provider' => 'openai', 'model_family' => 'codex', 'model' => 'gpt-6-sol', 'effort' => 'medium' }
    data = { 'version' => 1, 'merge' => { 'preference' => 'ask' },
             'review' => { 'required' => 'none', 'local_review_agents' => [agent] } }
    result = Shaka::Seam::FieldClassifier.new(data).call

    assert_empty result.blocking
    assert_equal [agent], result.established.dig('review', 'local_review_agents')
  end
end
