# frozen_string_literal: true

require_relative 'test_helper'
require 'fileutils'
require 'json'
require 'yaml'

module ReposCatalogHelpers
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def with_home
    Dir.mktmpdir('shaka-repos-home') do |home|
      Dir.mktmpdir('shaka-repos-roots') do |roots|
        @roots = roots
        yield home
      end
    end
  end

  def env(home)
    { 'SHAKA_HOME' => home, 'PATH' => ENV.fetch('PATH') }
  end

  def refresh(home)
    catalog, error, status = refresh_result(home)
    raise error unless status.success?

    catalog
  end

  def refresh_result(home)
    output, error, status = Open3.capture3(env(home), COMMAND, 'repos', 'refresh')
    path = File.join(home, 'catalog.json')
    catalog = File.file?(path) ? JSON.parse(File.read(path)) : {}
    [output.empty? ? catalog : JSON.parse(output), error, status]
  end

  def registered_repository(home, name:, prefix: nil, origin: nil)
    root = repository(name:, prefix:, origin:)
    _output, error, status = Open3.capture3(env(home), COMMAND, 'repos', 'add', '--root', root)
    raise error unless status.success?

    root
  end

  def repository(name:, prefix: nil, origin: nil, remote_head: true)
    root = File.join(@roots, name)
    write_seam(root, prefix)
    git_origin!(root, name, origin:, remote_head:)
    File.realpath(root)
  end

  def identities(catalog)
    catalog.fetch('repositories').map { |row| row.fetch('identity') }
  end

  def expected_row(name, root, prefix:, source:, url: nil)
    { 'identity' => "acme/#{name}", 'url' => url || "https://github.com/acme/#{name}",
      'root' => root, 'prefix' => prefix, 'prefix_source' => source }
  end

  private

  def write_seam(root, prefix)
    FileUtils.mkdir_p(File.join(root, '.agents/bin'))
    %w[setup validate test].each do |bin|
      path = File.join(root, '.agents/bin', bin)
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
    extra = prefix ? { 'repo_prefix' => prefix } : {}
    File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(seam_config.merge(extra)))
  end

  def git_origin!(root, name, origin: nil, remote_head: true)
    git!(root, 'init', '-b', 'main')
    git!(root, 'add', '.')
    git!(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', 'trusted')
    git!(root, 'remote', 'add', 'origin', origin || "https://github.com/acme/#{name}.git")
    git!(root, 'update-ref', 'refs/remotes/origin/main', 'HEAD')
    git!(root, 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main') if remote_head
  end

  def seam_config
    {
      'version' => 1, 'base_branch' => 'main',
      'review' => { 'required' => 'none' },
      'merge' => { 'preference' => 'ask' }
    }
  end

  def git!(root, *)
    output, status = Open3.capture2e('git', '-C', root, *)
    raise output unless status.success?
  end

  def omit_trusted_setup(root)
    FileUtils.rm(File.join(root, '.agents/bin/setup'))
    git!(root, 'add', '-A')
    git!(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-m', 'omit setup')
    git!(root, 'update-ref', 'refs/remotes/origin/main', 'HEAD')
    root
  end
end

class ReposCatalogTest < Minitest::Test
  include ReposCatalogHelpers

  def test_refresh_rebuilds_the_catalog_from_trusted_seams
    with_home do |home|
      first = registered_repository(home, name: 'alpha', prefix: 'ALP')
      second = registered_repository(home, name: 'beta')
      catalog = refresh(home)
      rows = [expected_row('alpha', first, prefix: 'ALP', source: 'seam'),
              expected_row('beta', second, prefix: 'BETA', source: 'fallback')]

      assert_equal rows, catalog.fetch('repositories')
      assert_empty catalog.fetch('duplicate_prefixes')
    end
  end

  def test_refresh_reconstructs_a_deleted_catalog
    with_home do |home|
      registered_repository(home, name: 'alpha', prefix: 'ALP')
      refresh(home)
      FileUtils.rm(File.join(home, 'catalog.json'))

      assert_equal ['acme/alpha'], identities(refresh(home))
    end
  end

  def test_direct_prefix_lookup_does_not_need_the_catalog
    with_home do |home|
      root = repository(name: 'solo', prefix: 'SOLO')
      output, error, status = Open3.capture3(env(home), COMMAND, 'prefix', '--root', root)

      assert_predicate status, :success?, error
      assert_equal({ 'prefix' => 'SOLO', 'source' => 'seam' }, JSON.parse(output))
      refute_path_exists File.join(home, 'catalog.json')
    end
  end

  def test_refresh_ignores_a_candidate_seam_and_reads_the_trusted_ref
    with_home do |home|
      root = registered_repository(home, name: 'alpha', prefix: 'TRUST')
      path = File.join(root, '.agents/agent-workflow.yml')
      File.write(path, File.read(path).sub('TRUST', 'DIRTY'))
      catalog = refresh(home)

      assert_equal 'TRUST', catalog.dig('repositories', 0, 'prefix')
      assert_equal 'seam', catalog.dig('repositories', 0, 'prefix_source')
    end
  end

  def test_refresh_does_not_treat_two_checkouts_of_one_repo_as_a_collision
    with_home do |home|
      first = registered_repository(home, name: 'alpha', prefix: 'ALP')
      second = File.join(@roots, 'alpha-checkout')
      FileUtils.cp_r(first, second)
      _output, error, status = Open3.capture3(env(home), COMMAND, 'repos', 'add', '--root', second)
      raise error unless status.success?

      catalog = refresh(home)
      assert_empty catalog.fetch('duplicate_prefixes')
      assert_equal %w[acme/alpha acme/alpha], identities(catalog)
    end
  end

  def test_refresh_reports_duplicate_prefixes_without_changing_identity
    with_home do |home|
      registered_repository(home, name: 'alpha', prefix: 'DUP')
      registered_repository(home, name: 'beta', prefix: 'DUP')
      catalog, error, status = refresh_result(home)

      refute_predicate status, :success?
      assert_includes error, 'DUP'
      assert_equal %w[github.com/acme/alpha github.com/acme/beta], catalog.dig('duplicate_prefixes', 'DUP')
      assert_equal %w[acme/alpha acme/beta], identities(catalog)
    end
  end

  def test_refresh_reports_the_same_owner_name_on_different_hosts_as_a_collision
    with_home do |home|
      registered_repository(home, name: 'repo', prefix: 'DUP')
      registered_repository(home, name: 'ghe-repo', prefix: 'DUP', origin: 'https://ghe.example/acme/repo.git')
      catalog, error, status = refresh_result(home)
      keys = catalog.dig('duplicate_prefixes', 'DUP')

      refute_predicate status, :success?
      assert_equal %w[ghe.example/acme/repo github.com/acme/repo], keys.sort
      assert_includes error, keys.first
      assert_equal %w[acme/repo acme/repo], identities(catalog)
    end
  end
end

class ReposCatalogOriginTest < Minitest::Test
  include ReposCatalogHelpers

  def test_refresh_catalogs_scp_enterprise_origins
    with_home do |home|
      root = registered_repository(home, name: 'repo', prefix: 'GHE', origin: 'git@ghe.example:acme/repo.git')
      catalog = refresh(home)

      assert_equal [expected_row('repo', root, prefix: 'GHE', source: 'seam', url: 'ssh://ghe.example/acme/repo')],
                   catalog.fetch('repositories')
    end
  end

  def test_refresh_reports_the_same_host_on_different_ports_as_a_collision
    with_home do |home|
      registered_repository(home, name: 'one', prefix: 'DUP', origin: 'https://ghe.example:8443/acme/repo.git')
      registered_repository(home, name: 'two', prefix: 'DUP', origin: 'https://ghe.example:9443/acme/repo.git')
      catalog, error, status = refresh_result(home)
      keys = catalog.dig('duplicate_prefixes', 'DUP')

      refute_predicate status, :success?
      assert_equal ['ghe.example:8443/acme/repo', 'ghe.example:9443/acme/repo'], keys.sort
      assert_includes error, keys.first
    end
  end

  def test_refresh_skips_a_missing_root_and_still_writes_other_rows
    with_home do |home|
      kept = registered_repository(home, name: 'alpha', prefix: 'ALP')
      gone = registered_repository(home, name: 'beta', prefix: 'BETA')
      FileUtils.rm_rf(gone)
      catalog, error, status = refresh_result(home)

      refute_predicate status, :success?
      assert_includes error, gone
      assert_equal [expected_row('alpha', kept, prefix: 'ALP', source: 'seam')], catalog.fetch('repositories')
    end
  end

  def test_refresh_still_reports_prefix_collisions_when_a_root_is_skipped
    with_home do |home|
      registered_repository(home, name: 'alpha', prefix: 'DUP')
      registered_repository(home, name: 'beta', prefix: 'DUP')
      gone = registered_repository(home, name: 'gone', prefix: 'GONE')
      FileUtils.rm_rf(gone)
      catalog, error, status = refresh_result(home)

      refute_predicate status, :success?
      assert_match(/#{Regexp.escape(gone)}.*DUP/m, error)
      assert_equal %w[github.com/acme/alpha github.com/acme/beta], catalog.dig('duplicate_prefixes', 'DUP')
    end
  end

  def test_refresh_treats_ssh_port_22_as_the_same_repository
    with_home do |home|
      registered_repository(home, name: 'scp', prefix: 'GHE', origin: 'git@ghe.example:acme/repo.git')
      registered_repository(home, name: 'ssh', prefix: 'GHE', origin: 'ssh://git@ghe.example:22/acme/repo.git')
      catalog = refresh(home)
      urls = catalog.fetch('repositories').map { |row| row.fetch('url') }.uniq

      assert_empty catalog.fetch('duplicate_prefixes')
      assert_equal ['ssh://ghe.example/acme/repo'], urls
    end
  end

  def test_refresh_treats_host_case_as_the_same_repository
    with_home do |home|
      registered_repository(home, name: 'repo', prefix: 'SAME')
      registered_repository(home, name: 'cased', prefix: 'SAME', origin: 'https://GitHub.com/acme/repo.git')
      catalog = refresh(home)

      assert_empty catalog.fetch('duplicate_prefixes')
      assert_equal %w[acme/repo acme/repo], identities(catalog)
    end
  end

  def test_refresh_treats_github_owner_name_case_as_the_same_repository
    with_home do |home|
      registered_repository(home, name: 'repo', prefix: 'SAME')
      registered_repository(home, name: 'cased', prefix: 'SAME', origin: 'https://github.com/Acme/Repo.git')
      catalog = refresh(home)

      assert_empty catalog.fetch('duplicate_prefixes')
    end
  end
end

class ReposCatalogSkipTest < Minitest::Test
  include ReposCatalogHelpers

  def test_refresh_treats_ghe_owner_name_case_as_the_same_repository
    with_home do |home|
      registered_repository(home, name: 'repo', prefix: 'SAME', origin: 'https://ghe.example/acme/repo.git')
      registered_repository(home, name: 'cased', prefix: 'SAME', origin: 'https://ghe.example/Acme/Repo.git')
      catalog = refresh(home)

      assert_empty catalog.fetch('duplicate_prefixes')
    end
  end

  def test_refresh_treats_a_trailing_host_dot_as_the_same_repository
    with_home do |home|
      registered_repository(home, name: 'repo', prefix: 'SAME')
      registered_repository(home, name: 'fqdn', prefix: 'SAME', origin: 'https://github.com./acme/repo.git')
      catalog = refresh(home)

      assert_empty catalog.fetch('duplicate_prefixes')
    end
  end

  def test_prefix_and_refresh_use_origin_main_without_origin_head
    with_home do |home|
      root = repository(name: 'solo', prefix: 'SOLO', remote_head: false)
      output, error, status = Open3.capture3(env(home), COMMAND, 'prefix', '--root', root)

      assert_predicate status, :success?, error
      assert_equal({ 'prefix' => 'SOLO', 'source' => 'seam' }, JSON.parse(output))

      _added, add_error, add_status = Open3.capture3(env(home), COMMAND, 'repos', 'add', '--root', root)
      raise add_error unless add_status.success?

      assert_equal ['acme/solo'], identities(refresh(home))
    end
  end

  def test_refresh_skips_an_origin_with_an_invalid_percent_escape
    with_home do |home|
      kept = registered_repository(home, name: 'alpha', prefix: 'ALP')
      broken = registered_repository(home, name: 'broken', prefix: 'BRK',
                                           origin: 'https://ghe.example/acme/repo%ZZ.git')
      catalog, error, status = refresh_result(home)

      refute_predicate status, :success?
      assert_includes error, broken
      assert_equal [expected_row('alpha', kept, prefix: 'ALP', source: 'seam')], catalog.fetch('repositories')
    end
  end

  def test_refresh_skips_a_trusted_ref_that_omits_setup
    with_home do |home|
      kept = registered_repository(home, name: 'alpha', prefix: 'ALP')
      broken = omit_trusted_setup(registered_repository(home, name: 'broken', prefix: 'BRK'))
      catalog, error, status = refresh_result(home)

      refute_predicate status, :success?
      assert_includes error, broken
      assert_includes error, '.agents/bin/setup'
      assert_equal [expected_row('alpha', kept, prefix: 'ALP', source: 'seam')], catalog.fetch('repositories')
    end
  end

  def test_refresh_skips_an_origin_with_an_unencoded_space
    with_home do |home|
      kept = registered_repository(home, name: 'alpha', prefix: 'ALP')
      broken = registered_repository(home, name: 'spaced', prefix: 'SPC',
                                           origin: 'https://ghe.example/acme/my repo.git')
      catalog, error, status = refresh_result(home)

      refute_predicate status, :success?
      assert_includes error, broken
      assert_equal [expected_row('alpha', kept, prefix: 'ALP', source: 'seam')], catalog.fetch('repositories')
    end
  end
end
