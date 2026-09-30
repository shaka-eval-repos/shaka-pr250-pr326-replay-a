# frozen_string_literal: true

require_relative 'install_support'

class InstallEdgeCasesTest < Minitest::Test
  include InstallTestSupport

  def test_origin_credentials_are_removed_from_source_identity
    commit_source
    root = File.join(@directory, 'source')
    git('-C', root, 'config', 'remote.origin.url', 'https://user:secret@example.com/team/shaka.git?token=other')
    install!

    assert_equal 'https://example.com/team/shaka.git', package_identity.fetch('source').fetch('repository')
    refute_includes JSON.generate(package_identity), 'secret'
  end

  def test_clean_source_with_unicode_filename_records_revision
    File.write(File.join(@source, 'café.md'), "tracked\n")
    commit_source
    install!

    assert_equal 'revision', package_identity.fetch('source').fetch('kind')
  end

  def test_ignored_local_file_is_excluded_from_the_managed_copy
    commit_source
    File.write(File.join(@directory, 'source', '.gitignore'), "skills/shaka/.env\n")
    File.write(File.join(@source, '.env'), 'local secret')
    install!

    assert_equal 'revision', package_identity.fetch('source').fetch('kind')
    assert_ignored_file_excluded
  end

  def test_hidden_worktree_edit_is_recorded_as_development
    commit_source
    root = File.join(@directory, 'source')
    git('-C', root, 'update-index', '--assume-unchanged', 'skills/shaka/SKILL.md')
    File.write(File.join(@source, 'SKILL.md'), 'hidden edit')
    install!

    assert_equal 'development', package_identity.fetch('source').fetch('kind')
  end

  def test_hidden_deleted_file_is_not_labelled_exact_revision
    path = File.join(@source, 'extra.md')
    File.write(path, "tracked\n")
    commit_source
    root = File.join(@directory, 'source')
    git('-C', root, 'update-index', '--assume-unchanged', 'skills/shaka/extra.md')
    File.unlink(path)
    install!

    assert_equal 'development', package_identity.fetch('source').fetch('kind')
  end

  def test_rollback_rejects_flags_that_would_mix_skill_versions
    install!
    id = package_identity.fetch('package_id')
    output, status = run_installer('--skills-dir', @skills_dir, '--rollback', id)

    refute_predicate status, :success?, output
    assert_includes output, 'Rollback flags must match'
  end

  def test_upgrade_replaces_a_changed_old_package
    install!
    old_package = package_path
    File.write(File.join(old_package, 'skills', 'shaka', 'extra'), 'unrelated file')
    File.write(File.join(@source, 'SKILL.md'), 'version two')
    install!

    refute_equal old_package, package_path
    assert_equal 'version two', skill_text
  end

  def test_doctor_reports_invalid_metadata_without_backtrace
    replace_fixture_with_full_skill
    output, status = run_installer('--skills-dir', @skills_dir)
    assert_predicate status, :success?, output
    corrupt_metadata
    output, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor',
                                     '--installation-json')

    refute_predicate status, :success?
    assert_includes output, 'Installed package metadata is invalid'
    refute_includes output, 'backtrace'
    assert_invalid_full_doctor_report
  end

  private

  def assert_ignored_file_excluded
    refute_path_exists File.join(package_path, 'skills', 'shaka', '.env')
    refute_includes File.read(File.join(package_path, '.shaka-install.json')), 'local secret'
  end

  def install!
    output, status = install
    assert_predicate status, :success?, output
  end

  def skill_text = File.read(File.join(@destination, 'SKILL.md'))

  def assert_invalid_full_doctor_report
    report, status = Open3.capture2e(File.join(@destination, 'scripts', 'shaka'), 'doctor')
    refute_predicate status, :success?
    assert_includes report, 'Shaka doctor: FAILED'
    assert_includes report, '[FAILED] Installation — Installed package metadata is invalid'
  end

  def corrupt_metadata
    File.write(File.join(package_path, '.shaka-install.json'),
               '{"version":"1","source":{"kind":"revision","content_sha256":"0","revision":null}}')
  end

  def commit_source
    root = File.join(@directory, 'source')
    git('init', '-q', root)
    git('-C', root, 'add', 'skills')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
  end
end
