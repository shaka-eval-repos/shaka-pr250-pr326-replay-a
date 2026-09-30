# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'shellwords'
require 'yaml'

# rubocop:disable-next Metrics/ClassLength
class ValidateWorkflowTest < Minitest::Test
  def setup
    @workflow = YAML.load_file(File.expand_path('../.github/workflows/validate.yml', __dir__))
    @steps = @workflow.dig('jobs', 'validate', 'steps')
    @detector_script = @steps.find { |step| step['id'] == 'changes' }.fetch('run')
    @codeql = YAML.load_file(File.expand_path('../.github/workflows/codeql.yml', __dir__))
    @codeql_steps = @codeql.dig('jobs', 'analyze', 'steps')
  end

  def test_runs_required_validation_for_pull_requests_merge_groups_and_main
    on = @workflow['on'] || @workflow[true]

    assert_includes on.keys, 'pull_request'
    assert_includes on.keys, 'merge_group'
    assert_equal ['main'], on.dig('push', 'branches')
  end

  def test_cancels_only_obsolete_pull_request_validation
    concurrency = @workflow.fetch('concurrency')
    expected_group = '${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}'

    assert_equal expected_group, concurrency.fetch('group')
    assert_equal "${{ github.event_name == 'pull_request' }}", concurrency.fetch('cancel-in-progress')
  end

  def test_checkout_has_the_history_needed_for_comparison
    assert_equal 0, step_using('actions/checkout@').dig('with', 'fetch-depth')
  end

  def test_detector_selects_the_base_for_each_event_type
    base = @steps.find { |step| step['id'] == 'changes' }.dig('env', 'SHAKA_BASE_REF')

    assert_includes base, "github.event_name == 'pull_request' && github.event.pull_request.base.sha"
    assert_includes base, "github.event_name == 'merge_group' && github.event.merge_group.base_sha"
    assert_includes base, 'github.event.before'
  end

  def test_detector_uses_the_shared_classifier
    assert_includes @detector_script, 'git diff --check'
    assert_includes @detector_script, 'git show "${SHAKA_BASE_REF}:bin/docs-only-change"'
    assert_includes @detector_script, '$RUNNER_TEMP/docs-only-change'
    refute_includes @detector_script, 'if bin/docs-only-change'
  end

  def test_ruby_setup_is_skipped_for_docs
    assert_docs_condition step_using('ruby/setup-ruby@')
  end

  def test_full_validation_is_skipped_for_docs
    assert_docs_condition(@steps.find { |step| step['run'] == 'bin/validate' })
  end

  def test_codeql_remains_always_on
    refute(@codeql_steps.any? { |step| step['id'] == 'changes' })
    refute step_using('github/codeql-action/init@', @codeql_steps).key?('if')
    refute step_using('github/codeql-action/analyze@', @codeql_steps).key?('if')
  end

  def test_local_validation_checks_untracked_document_whitespace
    root = validation_fixture
    File.write(File.join(root, 'docs/00-empty.md'), '')
    File.write(File.join(root, 'docs/99-bad.md'), "bad  \n")
    output, status = run_local_validation(root)
    refute_predicate status, :success?
    assert_includes output, 'trailing whitespace'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_local_validation_rejects_staged_whitespace_hidden_by_the_working_tree
    root = validation_fixture
    guide = File.join(root, 'docs/guide.md')
    File.write(guide, "bad  \n")
    git(root, 'add', 'docs/guide.md')
    File.write(guide, "# Guide\n")

    output, status = run_local_validation(root)

    refute_predicate status, :success?
    assert_includes output, 'trailing whitespace'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_local_validation_rejects_committed_whitespace_hidden_by_the_index
    root = validation_fixture
    hide_committed_guide_with_index(root, content: "bad  \n")

    output, status = run_local_validation(root, { 'SHAKA_BASE_REF' => 'HEAD^' })

    refute_predicate status, :success?
    assert_includes output, 'trailing whitespace'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_local_validation_rejects_committed_executable_doc_hidden_by_the_index
    root = validation_fixture
    hide_committed_guide_with_index(root, executable: true)

    output, status = run_local_validation(root, { 'SHAKA_BASE_REF' => 'HEAD^' })

    assert_predicate status, :success?, output
    assert_includes output, 'FULL_VALIDATION'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_local_validation_fails_when_untracked_inventory_fails
    root = validation_fixture
    File.write(File.join(root, 'docs/new.md'), "New\n")
    fake_git = install_failing_git(root, 'ls-files --others', 2, 'inventory failed', occurrence: 2)
    output, status = run_local_validation(root, { 'PATH' => "#{fake_git}:#{ENV.fetch('PATH')}" })
    refute_predicate status, :success?
    assert_includes output, 'inventory failed'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_local_validation_fails_when_untracked_whitespace_check_errors
    root = validation_fixture
    File.write(File.join(root, 'docs/new.md'), "New\n")
    fake_git = install_failing_git(root, 'diff --no-index', 1, 'Could not access untracked document')
    output, status = run_local_validation(root, { 'PATH' => "#{fake_git}:#{ENV.fetch('PATH')}" })

    refute_predicate status, :success?
    assert_includes output, 'Could not access untracked document'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_detector_falls_back_to_full_validation_for_an_unknown_base
    root = validation_fixture

    output, status, decision = run_detector(root, 'missing-base')

    assert_predicate status, :success?, output
    assert_equal "docs_only=false\n", decision
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_documentation_change_selects_lightweight_remote_validation
    root = validation_fixture
    File.write(File.join(root, 'docs/guide.md'), "# Clearer guide\n")

    output, status, decision = run_detector(root, 'HEAD')

    assert_predicate status, :success?, output
    assert_equal "docs_only=true\n", decision
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_detector_ignores_a_candidate_classifier_that_allows_code
    root = validation_fixture
    base = git(root, 'rev-parse', 'HEAD').strip
    File.write(File.join(root, 'bin/docs-only-change'), "#!/bin/sh\nexit 0\n")
    File.write(File.join(root, 'lib/example.rb'), "changed\n")

    output, status, decision = run_detector(root, base)

    assert_predicate status, :success?, output
    assert_equal "docs_only=false\n", decision
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_detector_falls_back_when_the_base_has_no_classifier
    root = validation_fixture
    git(root, 'rm', 'bin/docs-only-change')
    git(root, 'commit', '-qm', 'Remove classifier')
    base = git(root, 'rev-parse', 'HEAD').strip
    File.write(File.join(root, 'docs/guide.md'), "# Clearer guide\n")

    output, status, decision = run_detector(root, base)

    assert_predicate status, :success?, output
    assert_equal "docs_only=false\n", decision
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  def test_mixed_whitespace_change_runs_full_local_validation
    root = validation_fixture
    caller = validation_fixture
    File.write(File.join(root, 'lib/example.rb'), "bad  \n")
    File.write(File.join(root, 'bin/docs-only-change'), "#!/bin/sh\nexit 0\n")
    File.write(File.join(caller, 'docs/guide.md'), "Caller docs\n")

    output, _status = run_local_validation(root, {}, chdir: caller)

    assert_includes output, 'FULL_VALIDATION'
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
    FileUtils.remove_entry(caller) if caller && File.exist?(caller)
  end

  def test_mixed_whitespace_change_selects_full_remote_validation
    root = validation_fixture
    File.write(File.join(root, 'lib/example.rb'), "bad  \n")

    output, status, decision = run_detector(root, 'HEAD')

    assert_predicate status, :success?, output
    assert_equal "docs_only=false\n", decision
  ensure
    FileUtils.remove_entry(root) if root && File.exist?(root)
  end

  private

  def step_using(action, steps = @steps)
    steps.find { |step| step['uses']&.start_with?(action) }
  end

  def git(root, *)
    output, status = Open3.capture2e('git', *, chdir: root)
    raise output unless status.success?

    output
  end

  def validation_fixture
    root = Dir.mktmpdir('validate-docs')
    FileUtils.mkdir_p([File.join(root, '.agents/bin'), File.join(root, 'bin'), File.join(root, 'docs'),
                       File.join(root, 'lib')])
    install_validation_scripts(root)
    File.write(File.join(root, 'README.md'), "[Guide](docs/guide.md)\n")
    File.write(File.join(root, 'docs/guide.md'), "# Guide\n")
    root.tap { |path| initialize_repository(path) }
  end

  def hide_committed_guide_with_index(root, content: "# Guide\n", executable: false)
    guide = File.join(root, 'docs/guide.md')
    File.write(guide, content)
    FileUtils.chmod(0o755, guide) if executable
    git(root, 'add', 'docs/guide.md')
    git(root, 'commit', '-qm', 'Commit defective documentation')
    File.write(guide, "# Guide\n")
    FileUtils.chmod(0o644, guide)
    git(root, 'add', 'docs/guide.md')
  end

  def install_validation_scripts(root)
    FileUtils.cp(File.expand_path('../bin/docs-only-change', __dir__), File.join(root, 'bin/docs-only-change'))
    FileUtils.cp(File.expand_path('../.agents/bin/validate', __dir__), File.join(root, '.agents/bin/validate'))
    File.write(File.join(root, 'bin/validate'), "#!/bin/sh\necho FULL_VALIDATION\n")
    FileUtils.chmod(0o755, File.join(root, 'bin/validate'))
  end

  def initialize_repository(root)
    git(root, 'init', '-q')
    git(root, 'config', 'user.email', 'test@example.com')
    git(root, 'config', 'user.name', 'Test User')
    git(root, 'add', '.')
    git(root, 'commit', '-qm', 'Initial')
  end

  # rubocop:disable-next Metrics/MethodLength
  def install_failing_git(root, command, status, message, occurrence: 1)
    directory = File.join(root, '.git/fake-bin')
    FileUtils.mkdir_p(directory)
    counter = File.join(root, '.git/fake-git-counter')
    script = <<~SH
      #!/bin/sh
      case "$*" in
        *"#{command}"*)
          count=0
          [ ! -f #{Shellwords.escape(counter)} ] || read count < #{Shellwords.escape(counter)}
          count=$((count + 1))
          printf '%s\\n' "$count" > #{Shellwords.escape(counter)}
          [ "$count" -ne #{occurrence} ] || { printf '%s\\n' '#{message}' >&2; exit #{status}; }
          ;;
      esac
      exec #{Shellwords.escape(TEST_GIT)} "$@"
    SH
    File.write(File.join(directory, 'git'), script)
    FileUtils.chmod(0o755, File.join(directory, 'git'))
    directory
  end

  def run_local_validation(root, environment = {}, chdir: root)
    Open3.capture2e({ 'SHAKA_BASE_REF' => 'HEAD' }.merge(environment),
                    File.join(root, '.agents/bin/validate'), chdir:)
  end

  def run_detector(root, base)
    decision = File.join(root, 'decision')
    runner_temp = Dir.mktmpdir('validate-runner')
    script = File.join(runner_temp, 'detect-docs')
    File.write(script, @detector_script)
    env = { 'SHAKA_BASE_REF' => base, 'GITHUB_OUTPUT' => decision, 'RUNNER_TEMP' => runner_temp }
    output, status = Open3.capture2e(env, 'bash', '-euo', 'pipefail', script, chdir: root)
    [output, status, File.read(decision)]
  ensure
    FileUtils.remove_entry(runner_temp) if runner_temp && File.exist?(runner_temp)
  end

  def assert_docs_condition(step)
    assert_equal "steps.changes.outputs.docs_only != 'true'", step['if']
  end
end
