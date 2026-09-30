# frozen_string_literal: true

require_relative 'package_test_helpers'

class PackageTest < Minitest::Test
  include PackageTestHelpers

  def test_built_gem_runs_and_installs_its_skill_without_the_source_checkout
    archive = File.join(@directory, 'pilot.gem')
    run_gem('build', 'shaka.gemspec', '--output', archive, chdir: ROOT)
    run_gem('install', '--local', '--no-document', archive)
    check_commands
    source = install_skill
    %w[shaka rct mct-claude rct-claude].each { |name| File.unlink(File.join(@directory, 'pilot skills', name)) }
    run_gem('uninstall', 'shaka', '--all', '--executables', '--ignore-dependencies')
    refute_path_exists File.join(@home, 'bin', 'shaka')
    assert File.file?(File.join(source, 'SKILL.md'))
  end

  def test_built_gem_distributes_the_declared_license
    archive = File.join(@directory, 'licensed.gem')
    run_gem('build', 'shaka.gemspec', '--output', archive, chdir: ROOT)
    package = Gem::Package.new(archive)
    assert_equal ['MIT'], package.spec.licenses
    package.extract_files(File.join(@directory, 'unpacked'))
    license = File.join(@directory, 'unpacked', 'LICENSE')
    assert File.file?(license), 'The distributed gem must include its license'
    assert_equal File.read(File.join(ROOT, 'LICENSE')), File.read(license)
  end

  def test_built_gem_contains_the_guides_its_workflow_links_to
    archive = File.join(@directory, 'guides.gem')
    run_gem('build', 'shaka.gemspec', '--output', archive, chdir: ROOT)
    files = Gem::Package.new(archive).spec.files

    %w[docs/getting-started.md skills/shaka/references/review.md skills/shaka/references/writing.md
       contributing/packaging.md CONTRIBUTING.md].each do |path|
      assert_includes files, path
    end
  end

  def test_packaged_markdown_links_resolve_inside_the_package
    archive = File.join(@directory, 'links.gem')
    run_gem('build', 'shaka.gemspec', '--output', archive, chdir: ROOT)
    destination = File.join(@directory, 'links')
    Gem::Package.new(archive).extract_files(destination)

    assert_packaged_links(destination)
  end

  def test_built_gem_excludes_repository_internal_trust_files
    run_gem('build', 'shaka.gemspec', '--output', archive = File.join(@directory, 'trust.gem'), chdir: ROOT)
    refute_empty(files = Gem::Package.new(archive).spec.files)
    assert_empty files.grep(%r{\Ainternal/})
    [%r{(?:\A|/)trusted-github-actors\.ya?ml\z}, %r{\A\.agents/}].each { |pattern| assert_empty files.grep(pattern) }
  end

  def test_installed_gem_screens_public_comments_for_a_non_skill_consumer
    install_gem
    result = run_public_comments_consumer
    assert_equal([%w[maintainer writer]], result['issue_comments'].map { |row| row.values_at('author', 'trust') })
    assert_equal(%w[stranger helper[bot]], result['excluded_interactions'].map { |row| row['author'] })
    refute_includes JSON.generate(result['excluded_interactions']), 'comment 2'
  end

  private

  def run_public_comments_consumer
    consumer = File.join(ROOT, 'test', 'fixtures', 'public_comments_consumer.rb')
    result = JSON.parse(run_command(consumer, File.join(@directory, 'absent-machine-config.yml')))
    loaded = result.fetch('loaded_from')
    refute_empty loaded
    assert(loaded.all? { |path| path.start_with?(File.realpath(@home)) }, loaded)
    assert_empty(loaded.grep(%r{/(?:github|work|merge)\.rb\z|/scripts/shaka(?:\.rb)?\z}), loaded)
    result
  end

  def check_commands
    assert_includes run_executable('shaka', '--help'), 'Usage: shaka'
    workflow = run_executable('shaka', 'workflow')
    assert_includes workflow, '## 1. Intake'
    assert_includes workflow, '## 7. Finish'
    assert_match(/\]\(<[^>]+gem home[^>]+>\)/, workflow)
  end

  def check_public_skills(skills, source)
    check_shaka_skill(File.realpath(File.join(skills, 'shaka')), source)
    %w[rct mct-claude rct-claude].each do |name|
      tower = File.realpath(File.join(skills, name))
      assert File.file?(File.join(tower, 'SKILL.md')), name
      assert_equal File.dirname(source), File.dirname(tower)
    end
  end

  def check_shaka_skill(shaka, source)
    assert File.file?(File.join(shaka, 'SKILL.md'))
    assert File.file?(File.join(shaka, 'config', 'workflow.yml'))
    assert File.file?(File.join(shaka, 'references', 'shaka-issue-offer.md'))
    assert_equal source, shaka
  end

  def install_skill
    skills = File.join(@directory, 'pilot skills')
    run_executable('shaka-install', '--skills-dir', skills, '--with-rct', '--with-claude-towers')
    source = File.realpath(File.join(skills, 'shaka'))
    assert source.start_with?("#{File.realpath(@environment.fetch('HOME'))}/.local/share/shaka/installs/"), source
    check_public_skills(skills, source)
    assert File.file?(File.join(source, 'SKILL.md'))
    assert File.file?(File.join(source, 'scripts', 'shaka'))
    source
  end

  def run_executable(name, *)
    run_command(File.join(@home, 'bin', name), *)
  end
end
