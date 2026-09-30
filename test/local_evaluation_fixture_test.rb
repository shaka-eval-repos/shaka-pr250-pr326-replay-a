# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'yaml'
require 'shaka/doctor/bounded_command'
require 'shaka/repository_config'

module LocalEvaluationFixtureAssertions
  ROOT = File.expand_path('../eval/fixtures/local_evaluation', __dir__)
  FIXTURES = Dir.children(ROOT).sort.filter_map do |name|
    path = File.join(ROOT, name)
    [name, path] if File.directory?(path)
  end.to_h.freeze
  COMMON_FILES = %w[
    .agents/agent-workflow.yml .agents/bin/setup .agents/bin/test .agents/bin/validate
    .github/workflows/validate.yml .ruby-version AGENTS.md Gemfile Gemfile.lock fixture.yml
  ].freeze
  APP_FILES = {
    'probe' => %w[lib/color_swatch.rb test/color_swatch_test.rb],
    'feasibility' => %w[lib/trail_marker.rb test/trail_marker_test.rb]
  }.freeze
  MERGE_PREFERENCES = { 'probe' => 'auto', 'feasibility' => 'ask' }.freeze
  FIXTURE_RUNNER = Shaka::Doctor::BoundedCommand.new(timeout: 30)
  COMMANDS = { 'setup' => '.agents/bin/setup', 'validate' => '.agents/bin/validate',
               'test' => '.agents/bin/test' }.freeze
  EXPECTED_STEPS = [
    { 'uses' => 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1',
      'with' => { 'persist-credentials' => false } },
    { 'uses' => 'ruby/setup-ruby@95ef2b042f9d7a56d8268cba8559e2842e2ad01b',
      'with' => { 'ruby-version' => '.ruby-version', 'bundler-cache' => true } },
    { 'run' => '.agents/bin/validate' }
  ].freeze
  FORBIDDEN_CONTENT = /(?:AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|
                         -----BEGIN[ ][A-Z ]*PRIVATE[ ]KEY-----|(?:password|token|api[_-]?key|client[_-]?secret)\s*[:=]|
                         (?:internal|private)\s+notes?|raw\s+transcripts?|
                         hidden\s+assertions?|known[- ]bad\s+patch(?:es)?|
                         reference\s+(?:solution|assets?))/ix
  FORBIDDEN_WORKFLOW_INPUT = /\bsecrets\b|github(?:\.token\b|\s*\[\s*['"]token['"]\s*\])/i

  def application_files(name) = APP_FILES.fetch(name).map { |path| File.join(FIXTURES.fetch(name), path) }

  def assert_minimal_seam(root)
    config = Shaka::RepositoryConfig.load(root:)
    assert_equal 'main', config.base_branch
    assert_seam_policy(config, root)
    assert_runtime_pins(root)
  end

  def assert_seam_policy(config, root)
    expected_merge = MERGE_PREFERENCES.fetch(File.basename(root))
    assert_equal expected_merge, config.merge.fetch('preference')
    assert_equal COMMANDS, config.commands
    assert_equal 'none', config.review.fetch('required')
  end

  def assert_runtime_pins(root)
    assert_equal "3.4.6\n", File.read(File.join(root, '.ruby-version'))
    assert_equal ["source 'https://rubygems.org'", "gem 'minitest', '6.0.6'"], gemfile_lines(root)
    lock = File.read(File.join(root, 'Gemfile.lock'))
    assert_match(/^    minitest \(6\.0\.6\)$/, lock)
    assert_match(/^  minitest \(6\.0\.6\) sha256=[0-9a-f]{64}$/, lock)
  end

  def assert_minimal_workflow(root)
    workflow = YAML.safe_load_file(File.join(root, '.github/workflows/validate.yml'))
    assert_equal %w[jobs name on permissions], workflow.keys.sort
    job = assert_workflow_header(workflow)
    assert_equal %w[runs-on steps timeout-minutes], job.keys.sort
    assert_workflow_job(root, job)
  end

  def assert_workflow_header(workflow)
    assert_equal({ 'contents' => 'read' }, workflow.fetch('permissions'))
    assert_equal %w[pull_request push], workflow.fetch('on').keys.sort
    assert_equal ['main'], workflow.fetch('on').fetch('push').fetch('branches')
    assert_equal ['validate'], workflow.fetch('jobs').keys
    workflow.fetch('jobs').fetch('validate')
  end

  def assert_workflow_job(root, job)
    assert_operator job.fetch('timeout-minutes'), :<=, 5
    assert_equal EXPECTED_STEPS, job.fetch('steps')
    workflow = File.read(File.join(root, '.github/workflows/validate.yml'))
    refute_match FORBIDDEN_WORKFLOW_INPUT, workflow
  end

  def files(root)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: root)
       .reject { |path| File.directory?(File.join(root, path)) && !File.symlink?(File.join(root, path)) }
       .sort
  end

  def gemfile_lines(root)
    File.readlines(File.join(root, 'Gemfile'), chomp: true).grep_v(/\A(?:#|\z)/)
  end

  def setup_fixture(root)
    Dir.mktmpdir('shaka-fixture') do |directory|
      FileUtils.cp_r(root, directory)
      copy = File.join(directory, File.basename(root))
      lock = File.join(copy, 'Gemfile.lock')
      before = [File.read(lock), files(copy)]
      stdout, stderr, success = FIXTURE_RUNNER.call([File.join(copy, '.agents/bin/setup'), '--local'], Dir.tmpdir)
      assert success, "#{stdout}\n#{stderr}"
      assert_equal before, [File.read(lock), files(copy)]
    end
  end

  def capture_fixture_validation(root)
    command = File.join(root, '.agents/bin/validate')
    stdout, stderr, success = FIXTURE_RUNNER.call([command], Dir.tmpdir)
    ["#{stdout}\n#{stderr}", success]
  end

  def capture_fixture_test(root, path)
    command = File.join(root, '.agents/bin/test')
    stdout, stderr, success = FIXTURE_RUNNER.call([command, path], Dir.tmpdir)
    ["#{stdout}\n#{stderr}", success]
  end
end

class LocalEvaluationFixtureShapeTest < Minitest::Test
  include LocalEvaluationFixtureAssertions

  def test_fixtures_have_the_complete_small_public_shape
    FIXTURES.each do |name, root|
      paths = files(root)
      assert_equal (COMMON_FILES + APP_FILES.fetch(name)).sort, paths, name
      paths.each { |relative| refute File.symlink?(File.join(root, relative)), relative }
    end
  end

  def test_application_content_is_deliberately_distinct
    probe = application_files('probe')
    feasibility = application_files('feasibility')
    assert_empty probe.map { |path| File.read(path) } & feasibility.map { |path| File.read(path) }
    probe_guide = File.read(File.join(FIXTURES.fetch('probe'), 'AGENTS.md'))
    feasibility_guide = File.read(File.join(FIXTURES.fetch('feasibility'), 'AGENTS.md'))
    refute_equal probe_guide, feasibility_guide
  end

  def test_forbidden_content_detector_covers_each_material_type
    examples = ['-----BEGIN RSA PRIVATE KEY-----', 'internal notes', 'private notes',
                'raw transcript', 'hidden assertion',
                'reference solution', 'reference asset', 'known-bad patch', 'AKIA1234567890ABCDEF', "ghp_#{'a' * 20}",
                "github_pat_#{'a' * 20}", 'token = placeholder']
    examples.each { |example| assert_match FORBIDDEN_CONTENT, example }
    ['SECRETS.MY_TOKEN', "secrets['MY_TOKEN']", 'toJSON(secrets)', "github['token']"].each do |example|
      assert_match FORBIDDEN_WORKFLOW_INPUT, example
    end
  end

  def test_fixtures_contain_no_private_evaluation_material_or_credentials
    FIXTURES.each_value do |root|
      files(root).each do |relative|
        refute_match %r{(^|/)(?:secrets?|credentials?|transcripts?|hidden|references?|private|internal)(/|\.|$)}i,
                     relative
        refute_match FORBIDDEN_CONTENT, File.read(File.join(root, relative), encoding: 'UTF-8'), relative
      end
    end
  end

  def test_fixtures_explicitly_forbid_measured_case_reuse
    FIXTURES.each do |name, root|
      fixture = YAML.safe_load_file(File.join(root, 'fixture.yml'))
      assert_equal 1, fixture.fetch('version')
      assert_equal "slice_0_#{name}", fixture.fetch('purpose')
      assert_true fixture.fetch('public_safe'), name
      assert_false fixture.fetch('reusable_for_measured_cases'), name
    end
  end
end

class LocalEvaluationFixtureExecutionTest < Minitest::Test
  include LocalEvaluationFixtureAssertions

  def test_fixture_seams_and_workflows_preserve_the_minimal_policy
    FIXTURES.each_value do |root|
      assert_minimal_seam(root)
      assert_minimal_workflow(root)
    end
  end

  def test_fixture_setup_can_run_offline_and_leaves_the_tree_unchanged
    FIXTURES.each_value { |root| setup_fixture(root) }
  end

  def test_fixture_validation_stays_within_the_small_fixture_boundary
    FIXTURES.each_value do |root|
      output, success = capture_fixture_validation(root)
      assert success, output
      assert_match(/[1-9]\d* runs?, \d+ assertions?, 0 failures, 0 errors, 0 skips/, output)
    end
  end

  def test_fixture_test_commands_accept_focused_paths
    FIXTURES.each do |name, root|
      path = APP_FILES.fetch(name).find { |candidate| candidate.start_with?('test/') }
      output, success = capture_fixture_test(root, path)
      assert success, output
      assert_match(/\b1 runs?\b, \d+ assertions?, 0 failures, 0 errors, 0 skips/, output)
    end
  end
end
