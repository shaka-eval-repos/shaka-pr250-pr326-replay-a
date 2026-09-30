# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/git_origin'

class GitOriginTest < Minitest::Test
  def test_repository_name_from_https_and_scp_urls
    assert_equal 'agent-workflows', Shaka::GitOrigin.repository_name_from('https://github.com/acme/agent-workflows.git')
    assert_equal 'agent-workflows', Shaka::GitOrigin.repository_name_from('git@github.com:acme/agent-workflows.git')
    assert_equal 'shaka', Shaka::GitOrigin.repository_name_from('ssh://git@github.com/shakacode/shaka.git')
    assert_equal 'beta', Shaka::GitOrigin.repository_name_from('https://user:token@github.com/acme/beta.git')
  end

  def test_canonical_url_rewrites_only_the_github_host
    assert_equal 'https://github.com/acme/alpha',
                 Shaka::GitOrigin.canonical_url('git@github.com:acme/alpha.git')
    assert_equal 'https://notgithub.com/acme/beta',
                 Shaka::GitOrigin.canonical_url('https://notgithub.com/acme/beta.git')
    assert_equal 'https://gist.github.com/acme/beta',
                 Shaka::GitOrigin.canonical_url('https://gist.github.com/acme/beta.git')
  end

  def test_canonical_url_strips_userinfo_on_every_host
    assert_equal 'https://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://user:token@ghe.example/acme/repo.git')
    assert_equal 'https://github.com/acme/beta',
                 Shaka::GitOrigin.canonical_url('https://user:token@github.com/acme/beta.git')
    assert_equal 'https://ghe.example:8443/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://user:token@ghe.example:8443/acme/repo.git')
  end

  def test_canonical_url_strips_ssh_userinfo
    assert_equal 'ssh://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('ssh://user:token@ghe.example/acme/repo.git')
    assert_equal 'ssh://ghe.example:2222/acme/repo',
                 Shaka::GitOrigin.canonical_url('ssh://user:token@ghe.example:2222/acme/repo.git')
    assert_equal 'ssh://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('ssh://git@ghe.example/acme/repo.git')
    assert_equal 'ssh://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('ssh://git@ghe.example:22/acme/repo.git')
  end

  def test_identity_from_urls_with_an_authority_port
    assert_equal 'acme/repo', Shaka::GitOrigin.identity('https://ghe.example:8443/acme/repo.git')
    assert_equal 'acme/repo', Shaka::GitOrigin.identity('ssh://git@ghe.example:2222/acme/repo.git')
  end

  def test_identity_from_scp_url_without_a_username
    assert_equal 'acme/repo', Shaka::GitOrigin.identity('ghe.example:acme/repo.git')
    assert_equal 'ssh://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('ghe.example:acme/repo.git')
    assert_equal 'https://github.com/acme/repo',
                 Shaka::GitOrigin.canonical_url('github.com:acme/repo.git')
  end

  def test_canonical_url_discards_query_and_fragment
    secret = 'https://ghe.example/acme/repo.git?access_token=SECRET'
    assert_equal 'acme/repo', Shaka::GitOrigin.identity(secret)
    assert_equal 'https://ghe.example/acme/repo', Shaka::GitOrigin.canonical_url(secret)
    assert_equal 'https://github.com/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://github.com/acme/repo.git?access_token=SECRET')
    assert_equal 'https://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://ghe.example/acme/repo.git#ignored')
  end

  def test_canonical_url_uses_the_host_after_the_last_userinfo_at
    doubled = 'https://user@evil@github.com/acme/repo.git'
    assert_equal 'acme/repo', Shaka::GitOrigin.identity(doubled)
    assert_equal 'https://github.com/acme/repo', Shaka::GitOrigin.canonical_url(doubled)
  end

  def test_identity_from_scp_url_with_a_non_git_user
    assert_equal 'acme/repo', Shaka::GitOrigin.identity('deploy@ghe.example:acme/repo.git')
    assert_equal 'ssh://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('deploy@ghe.example:acme/repo.git')
  end

  def test_canonical_url_keeps_a_non_default_github_port
    assert_equal 'https://github.com:8443/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://github.com:8443/acme/repo.git')
  end
end

class GitOriginParseTest < Minitest::Test
  def test_canonical_url_omits_scheme_default_ports
    assert_equal 'https://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://ghe.example:443/acme/repo.git')
    assert_equal 'http://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('http://ghe.example:80/acme/repo.git')
    assert_equal 'http://ghe.example:443/acme/repo',
                 Shaka::GitOrigin.canonical_url('http://ghe.example:443/acme/repo.git')
  end

  def test_canonical_url_strips_a_trailing_root_dot_from_the_host
    assert_equal 'https://github.com/acme/repo',
                 Shaka::GitOrigin.canonical_url('https://github.com./acme/repo.git')
    assert_equal 'ssh://ghe.example/acme/repo',
                 Shaka::GitOrigin.canonical_url('ssh://git@ghe.example./acme/repo.git')
  end

  def test_parse_errors_do_not_echo_credentials
    error = assert_raises(Shaka::Error) do
      Shaka::GitOrigin.identity('https://user:SECRET@ghe.example/group/sub/repo.git?token=MORE')
    end

    assert_includes error.message, 'https://ghe.example/group/sub/repo.git'
    refute_includes error.message, 'SECRET'
    refute_includes error.message, 'MORE'
  end

  def test_parse_errors_do_not_echo_scp_userinfo
    error = assert_raises(Shaka::Error) do
      Shaka::GitOrigin.identity('TOKEN@ghe.example:group/sub/repo.git')
    end

    assert_includes error.message, 'ghe.example:group/sub/repo.git'
    refute_includes error.message, 'TOKEN'
  end

  def test_parse_errors_do_not_echo_nested_scp_userinfo
    error = assert_raises(Shaka::Error) do
      Shaka::GitOrigin.identity('user@SECRET@ghe.example:group/sub/repo.git')
    end

    assert_includes error.message, 'ghe.example:group/sub/repo.git'
    refute_includes error.message, 'SECRET'
  end

  def test_identity_rejects_an_invalid_percent_escape
    error = assert_raises(Shaka::Error) do
      Shaka::GitOrigin.identity('https://ghe.example/acme/repo%ZZ.git')
    end

    assert_includes error.message, 'ghe.example'
  end

  def test_identity_rejects_an_unencoded_space
    error = assert_raises(Shaka::Error) do
      Shaka::GitOrigin.identity('https://ghe.example/acme/my repo.git')
    end

    assert_includes error.message, 'ghe.example'
  end
end
