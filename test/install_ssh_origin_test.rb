# frozen_string_literal: true

require_relative 'install_support'
require 'shaka/workflow_version'

# An ssh:// origin is a standard clone spelling, so the installer records it like HTTP.
class InstallSshOriginTest < Minitest::Test
  include InstallTestSupport

  ORIGINS = {
    'ssh://git@github.com/shakacode/shaka.git' => 'ssh://git@github.com/shakacode/shaka.git',
    'ssh://github.com/shakacode/shaka.git' => 'ssh://github.com/shakacode/shaka.git',
    'ssh://git@github.com:22/shakacode/shaka.git' => 'ssh://git@github.com/shakacode/shaka.git',
    'ssh://git@example.com:2222/team/shaka.git' => 'ssh://git@example.com:2222/team/shaka.git',
    'ssh://git:secret@example.com/team/shaka.git?token=other#x' => 'ssh://git@example.com/team/shaka.git',
    'ssh://alice@example.com/team/shaka.git' => 'ssh://example.com/team/shaka.git'
  }.freeze

  def test_ssh_origin_is_recorded_without_secrets_personal_user_or_default_port
    commit_source
    ORIGINS.each do |origin, recorded|
      use_origin(origin)
      install!

      assert_equal recorded, package_identity.fetch('source').fetch('repository'), origin
      refute_match(/secret|alice/, JSON.generate(package_identity))
    end
  end

  def test_revision_installed_from_an_ssh_origin_links_its_commit
    commit_source
    use_origin('ssh://git@github.com/shakacode/shaka.git')
    install!

    assert_match %r{\A\[`\h{7}`\]\(https://github\.com/shakacode/shaka/commit/\h{40}\)\z},
                 Shaka::WorkflowVersion.current(identity: package_identity).markdown
  end

  private

  def install!
    output, status = install
    assert_predicate status, :success?, output
  end

  def use_origin(url) = git('-C', File.join(@directory, 'source'), 'config', 'remote.origin.url', url)

  def commit_source
    root = File.join(@directory, 'source')
    git('init', '-q', root)
    git('-C', root, 'add', 'skills')
    git('-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
  end
end
