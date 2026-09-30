# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'yaml'
require_relative 'repository_fixture'
require 'shaka/repository_config'
require 'shaka/trusted_config_source'
require 'shaka/seam/field_classifier'

# A repository's review instructions, read from the trusted commit and chosen per reviewer.
# Builds a repository whose trusted commit configures review prompts, and runs review run on it.
module ReviewPromptFileFixture
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  private

  def review_prompt(root, base, head, bin)
    output, error, status = run_review(root, base, head, bin)
    assert_predicate status, :success?, "#{output}\n#{error}"
    File.unlink(JSON.parse(output).fetch('report'))
    # The diff shows both versions of a changed prompt file as data; only the instructions matter here.
    JSON.parse(File.read(File.join(root, 'trace.json'))).fetch('prompt').split('SUPPORTING SOURCE DATA').first
  end

  def run_review(root, base, head, bin, *options)
    Open3.capture3({ 'PATH' => "#{bin}:#{ENV.fetch('PATH')}", 'REVIEW_TRACE' => File.join(root, 'trace.json') },
                   COMMAND, 'review', 'run', '--root', root, '--base', base, '--head', head,
                   '--reviewer', 'openai/codex', '--criteria-ref', base, *options)
  end

  # Delegates to the real Git but stalls on the tree lookup that resolves a prompt file path.
  def stall_prompt_lookup(bin)
    write_executable(bin, 'git', <<~SH)
      #!/bin/sh
      case "$*" in *"ls-tree -z"*) sleep 6 ;; esac
      exec #{TEST_GIT} "$@"
    SH
  end

  def with_repository(review = {}, commands: true)
    Dir.mktmpdir('shaka-review-prompt-file') do |root|
      Dir.mktmpdir('shaka-review-prompt-cli') do |bin|
        base = trusted_commit(root, review, commands)
        File.write(File.join(root, '.agents/review-prompt.md'), "Candidate instructions\n")
        commit!(root, 'candidate change')
        fake_codex(bin, git!(root, 'rev-parse', 'HEAD').strip)
        yield root, base, git!(root, 'rev-parse', 'HEAD').strip, bin
      end
    end
  end

  def trusted_commit(root, review, commands)
    git!(root, 'init')
    FileUtils.mkdir_p(File.join(root, '.agents/bin'))
    if commands
      %w[setup validate test].each { |name| write_executable(File.join(root, '.agents/bin'), name, "#!/bin/sh\n") }
    end
    write_trusted_files(root, review)
    commit!(root, 'trusted')
    git!(root, 'rev-parse', 'HEAD').strip
  end

  def write_trusted_files(root, review)
    File.write(File.join(root, '.agents/review-prompt.md'), "Trusted repository instructions\n")
    File.write(File.join(root, '.agents/codex-prompt.md'), "Codex-only instructions\n")
    File.write(File.join(root, '.agents/empty-prompt.md'), "\n")
    File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(seam(review)))
  end

  def seam(review)
    { 'version' => 1, 'merge' => { 'preference' => 'ask' },
      'review' => { 'required' => 'none' }.merge(review) }
  end

  def fake_codex(bin, head)
    write_executable(bin, 'codex', <<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      File.write(ENV.fetch('REVIEW_TRACE'), JSON.generate({ prompt: STDIN.read }))
      File.write(ARGV.fetch(ARGV.index('-o') + 1), "no findings\\nREVIEWED #{head} BY openai/codex EFFORT UNKNOWN FINDINGS 0\\n")
    RUBY
  end

  def write_executable(directory, name, script)
    path = File.join(directory, name)
    File.write(path, script)
    File.chmod(0o755, path)
  end

  def commit!(root, message)
    git!(root, 'add', '.')
    git!(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', message)
  end

  def git!(root, *)
    output, status = Open3.capture2e(TEST_GIT, '-C', root, *)
    raise output unless status.success?

    output
  end
end

class ReviewPromptFileTest < Minitest::Test
  include ReviewPromptFileFixture

  # The PR under review cannot change the instructions it is reviewed with.
  def test_uses_the_repository_prompt_file_from_the_trusted_commit
    with_repository({ 'prompt_file' => '.agents/review-prompt.md' }) do |root, base, head, bin|
      prompt = review_prompt(root, base, head, bin)

      assert_includes prompt, 'Trusted repository instructions'
      refute_includes prompt, 'Candidate instructions'
      assert_includes prompt, 'Make no edits.'
    end
  end

  def test_a_reviewer_prompt_file_overrides_the_repository_prompt_file
    agents = [{ 'provider' => 'openai', 'model_family' => 'codex', 'prompt_file' => '.agents/codex-prompt.md' }]
    review = { 'prompt_file' => '.agents/review-prompt.md', 'local_review_agents' => agents }
    with_repository(review) do |root, base, head, bin|
      prompt = review_prompt(root, base, head, bin)

      assert_includes prompt, 'Codex-only instructions'
      refute_includes prompt, 'Trusted repository instructions'
    end
  end

  # Reading one review setting must not make the review depend on the rest of the seam being valid.
  def test_reads_the_prompt_file_when_other_settings_at_the_trusted_commit_are_incomplete
    with_repository({ 'prompt_file' => '.agents/review-prompt.md' }, commands: false) do |root, base, head, bin|
      assert_includes review_prompt(root, base, head, bin), 'Trusted repository instructions'
    end
  end

  def test_keeps_the_default_instructions_without_a_prompt_file
    with_repository do |root, base, head, bin|
      assert_includes review_prompt(root, base, head, bin), 'Contract drift'
    end
  end

  def test_an_unusable_prompt_file_stops_the_review_with_the_reason
    with_repository({ 'prompt_file' => '.agents/empty-prompt.md' }) do |root, base, head, bin|
      reason = JSON.parse(run_review(root, base, head, bin).first).fetch('reason')

      assert_includes reason, '.agents/empty-prompt.md'
      assert_includes reason, 'is empty'
    end
  end

  def test_a_stalled_prompt_lookup_is_bounded_by_the_review_timeout
    with_repository({ 'prompt_file' => '.agents/review-prompt.md' }) do |root, base, head, bin|
      stall_prompt_lookup(bin)
      result = JSON.parse(run_review(root, base, head, bin, '--timeout-seconds', '2').first)

      assert_equal 'setup_failure', result.fetch('failure_stage')
      assert_includes result.fetch('reason'), 'timed out'
    end
  end

  def test_a_missing_prompt_file_stops_the_review_before_launch
    with_repository({ 'prompt_file' => '.agents/absent.md' }) do |root, base, head, bin|
      output, = run_review(root, base, head, bin)
      result = JSON.parse(output)

      assert_equal 'setup_failure', result.fetch('failure_stage')
      assert_includes result.fetch('reason'), '.agents/absent.md'
      refute_path_exists File.join(root, 'trace.json')
    end
  end
end

# The settings that name review instructions.
class ReviewPromptFileSchemaTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_loads_repository_and_reviewer_prompt_files
    agents = [reviewers.first.merge('prompt_file' => '.agents/codex-prompt.md'), reviewers.last]
    policy = review_policy('prompt_file' => '.agents/review-prompt.md', 'local_review_agents' => agents)
    with_repository('review' => policy) do |root|
      write_prompts(root)
      review = Shaka::RepositoryConfig.load(root:).review

      assert_equal '.agents/review-prompt.md', review.fetch('prompt_file')
      assert_equal '.agents/codex-prompt.md', review.fetch('local_review_agents').first.fetch('prompt_file')
    end
  end

  def test_rejects_a_prompt_file_outside_the_repository
    with_repository('review' => review_policy('prompt_file' => '../shared/review-prompt.md')) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.prompt_file must be a path inside the repository'
    end
  end

  # A setting that names a missing file would stop every review, including the one for its fix.
  def test_rejects_a_prompt_file_missing_from_the_checkout
    with_repository('review' => review_policy('prompt_file' => '.agents/absent.md')) do |root|
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.prompt_file does not exist'
    end
  end

  def test_rejects_a_prompt_file_missing_from_the_trusted_commit
    agents = [reviewers.first.merge('prompt_file' => '.agents/absent.md')]
    with_repository('review' => review_policy('local_review_agents' => agents)) do |root|
      commit(root)
      error = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.load(root:, ref: 'HEAD') }

      assert_includes error.message, 'review.local_review_agents[0].prompt_file does not name a file'
    end
  end

  def test_rejects_an_empty_prompt_file_in_the_checkout
    with_repository('review' => review_policy('prompt_file' => '.agents/empty.md')) do |root|
      File.write(File.join(root, '.agents/empty.md'), "\n")
      message = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }.message

      assert_includes message, 'review.prompt_file .agents/empty.md is empty'
    end
  end

  def test_rejects_an_empty_prompt_file_at_the_trusted_commit
    with_repository('review' => review_policy('prompt_file' => '.agents/empty.md')) do |root|
      File.write(File.join(root, '.agents/empty.md'), "\n")
      commit(root)
      error = assert_raises(Shaka::Error) { Shaka::TrustedConfigSource.load(root:, ref: 'HEAD') }

      assert_includes error.message, 'is empty'
    end
  end

  private

  def write_prompts(root)
    %w[review-prompt codex-prompt].each { |name| File.write(File.join(root, ".agents/#{name}.md"), "Focus\n") }
  end

  def commit(root)
    [%w[init --quiet], %w[add .], %w[-c user.name=Test -c user.email=test@example.com commit --quiet -m trusted]]
      .each { |arguments| system('git', '-C', root, *arguments, exception: true) }
  end
end

# Upgrading a seam keeps the review prompt setting.
class ReviewPromptFileMigrationTest < Minitest::Test
  def test_migration_retains_the_prompt_file
    data = { 'version' => 1, 'merge' => { 'preference' => 'ask' },
             'review' => { 'required' => 'none', 'prompt_file' => '.agents/review-prompt.md' } }
    result = Shaka::Seam::FieldClassifier.new(data).call

    assert_empty result.blocking
    assert_equal '.agents/review-prompt.md', result.established.dig('review', 'prompt_file')
  end
end

# The published review summary names the instructions the reviewer received.
class ReviewPromptSourceTest < Minitest::Test
  include ReviewPromptFileFixture

  def test_reports_which_instructions_the_reviewer_received
    agents = [{ 'provider' => 'openai', 'model_family' => 'codex', 'prompt_file' => '.agents/codex-prompt.md' }]
    sources = { {} => 'Shaka default',
                { 'prompt_file' => '.agents/review-prompt.md' } => 'review.prompt_file .agents/review-prompt.md',
                { 'local_review_agents' => agents } => 'openai/codex prompt_file .agents/codex-prompt.md' }
    sources.each { |review, source| assert_prompt_source(review, source) }
  end

  private

  def assert_prompt_source(review, source)
    with_repository(review) do |root, base, head, bin|
      result = JSON.parse(run_review(root, base, head, bin).first)
      File.unlink(result.fetch('report'))

      # This fixture has no AGENTS.md, so the requested ref supplied no criteria.
      assert_equal [source, nil], result.values_at('prompt_source', 'criteria_ref')
    end
  end
end
