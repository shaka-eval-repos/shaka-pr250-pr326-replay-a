# frozen_string_literal: true

require_relative 'test_helper'
require 'English'
require 'fileutils'
require 'pty'
require 'socket'
require 'timeout'
require_relative '../eval/lib/shaka/evaluation/probe_container'

module LocalEvaluationProbeHelpers
  ROOT = File.expand_path('..', __dir__)
  FIXTURE = File.join(ROOT, 'eval/fixtures/local_evaluation/probe')

  def new_container(trusted_skill:)
    Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill:)
  end

  def fixture_files(root)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: root)
       .reject { |path| File.directory?(File.join(root, path)) }
       .sort
  end

  def clean_environment(home, fake_bin)
    { 'HOME' => home, 'PATH' => "#{fake_bin}:#{ENV.fetch('PATH')}", 'GH_TOKEN' => nil,
      'GITHUB_TOKEN' => nil, 'SSH_AUTH_SOCK' => nil }.merge(
        Shaka::Evaluation::PROXY_VARIABLES.to_h { |variable| [variable, nil] }
      )
  end

  def write_executable(directory, name, body)
    path = File.join(directory, name)
    File.write(path, body)
    FileUtils.chmod(0o755, path)
  end
end

class LocalEvaluationProbeContainerPlanTest < Minitest::Test
  include LocalEvaluationProbeHelpers

  def setup
    @trusted_skill = File.realpath(Dir.mktmpdir('trusted-shaka'))
    FileUtils.mkdir_p(File.join(@trusted_skill, 'scripts'))
    write_executable(File.join(@trusted_skill, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
    @container = new_container(trusted_skill: @trusted_skill)
  end

  def teardown
    FileUtils.remove_entry(@trusted_skill)
  end

  def test_create_plan_exposes_only_the_fixture_helper_and_disposable_workspace
    command = @container.create_command('shaka-slice0-probe-test')
    mounts = command.each_index.filter_map { |index| command[index + 1] if command[index] == '--mount' }

    assert_equal expected_mounts, mounts
    assert_includes command, '--read-only'
    assert_includes command, 'no-new-privileges'
    assert_includes command, 'ALL'
    refute(command.any? { |argument| argument.include?('.ssh') || argument.include?('docker.sock') })
  end

  def test_lifecycle_commands_use_only_the_disposable_name_and_local_image
    assert_equal ['docker', 'build', '--tag', 'shaka-slice0-probe:local',
                  File.join(ROOT, 'eval/docker/slice-0-probe')], @container.build_command
  end

  def test_create_plan_keeps_credentials_out_of_arguments_and_uses_ephemeral_home
    command = @container.create_command('shaka-slice0-probe-test')

    assert_includes command, 'HOME=/home/shaka'
    assert_includes command, 'TMPDIR=/workspace/tmp'
    assert_includes command, '/home/shaka:rw,noexec,nosuid,nodev,mode=0700,uid=100,gid=101'
    assert_includes command, '/usr/local/bundle:rw,exec,nosuid,nodev,mode=0700,uid=100,gid=101'
    Shaka::Evaluation::PROXY_VARIABLES.each do |variable|
      assert_includes command.each_cons(2).to_a, ['--env', "#{variable}="]
    end
    refute(command.any? { |argument| argument.match?(/token|github_pat_|ssh_auth_sock/i) })
  end

  def test_auth_and_preflight_keep_sensitive_values_on_stdin
    name = 'shaka-slice0-probe-test'

    assert_equal %W[docker exec #{name} probe-reset], @container.prepare_command(name)
    assert_equal %w[docker exec -i shaka-slice0-probe-test gh auth login --hostname github.com --with-token],
                 @container.auth_command(name)
    assert_equal %w[docker exec shaka-slice0-probe-test gh auth setup-git],
                 @container.git_auth_command(name)
    assert_equal ['docker', 'exec', '-i', name, 'probe-preflight', 'shakacode/public-probe',
                  'shaka-eval-machine'],
                 @container.preflight_command(name, target: 'shakacode/public-probe',
                                                    login: 'shaka-eval-machine')
  end

  def test_owner_side_preflight_confirms_the_private_sibling
    assert_equal %w[gh api user --jq .login], @container.owner_identity_command
    assert_equal %w[gh api repos/shakacode/private-sibling --jq .visibility],
                 @container.owner_repository_command('shakacode/private-sibling')
    assert_equal %w[gh api orgs/shakacode/members/shaka-eval-machine --silent],
                 @container.owner_membership_command(target: 'shakacode/public-probe',
                                                     login: 'shaka-eval-machine')
    assert_raises(ArgumentError) { @container.owner_repository_command('shakacode/one/two') }
    assert_raises(ArgumentError) { @container.owner_repository_command('../..') }
  end

  def test_preflight_command_rejects_an_invalid_login
    assert_raises(ArgumentError) do
      @container.preflight_command('shaka-slice0-probe-test', target: 'shakacode/probe', login: '../owner')
    end
  end

  def test_cleanup_plan_can_target_only_a_slice_zero_probe_container
    assert_equal [
      %w[docker rm --force --volumes shaka-slice0-probe-test]
    ], @container.cleanup_commands('shaka-slice0-probe-test')

    error = assert_raises(ArgumentError) { @container.cleanup_commands('shared-development') }
    assert_match(/disposable Slice 0 probe name/, error.message)
  end

  private

  def expected_mounts
    ["type=bind,src=#{FIXTURE},dst=/seed/probe,readonly",
     "type=bind,src=#{@trusted_skill},dst=/opt/shaka,readonly",
     'type=volume,dst=/workspace']
  end
end

class LocalEvaluationTrustedSkillTest < Minitest::Test
  include LocalEvaluationProbeHelpers

  def test_candidate_checkout_cannot_supply_the_trusted_helper
    candidate_skill = File.join(ROOT, 'skills/shaka')
    container = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: candidate_skill)

    error = assert_raises(ArgumentError) { container.create_command('shaka-slice0-probe-test') }
    assert_match(/outside the candidate checkout/, error.message)
  end

  def test_trusted_helper_cannot_be_an_ancestor_or_an_unrelated_directory
    ancestor = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: File.dirname(ROOT))
    assert_raises(ArgumentError) { ancestor.create_command('shaka-slice0-probe-test') }

    root_mount = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: '/')
    assert_raises(ArgumentError) { root_mount.create_command('shaka-slice0-probe-test') }

    Dir.mktmpdir('not-a-skill') do |directory|
      unrelated = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: directory)
      assert_raises(ArgumentError) { unrelated.create_command('shaka-slice0-probe-test') }
    end
  end

  def test_trusted_helper_rejects_a_valid_skill_that_is_an_ancestor_of_the_checkout
    Dir.mktmpdir('trusted-parent') do |parent|
      root = File.join(parent, 'candidate')
      FileUtils.mkdir_p(File.join(parent, 'scripts'))
      FileUtils.mkdir_p(File.join(root, 'eval/fixtures/local_evaluation/probe'))
      write_executable(File.join(parent, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
      container = Shaka::Evaluation::ProbeContainer.new(root:, trusted_skill: parent)

      error = assert_raises(ArgumentError) { container.create_command('shaka-slice0-probe-test') }
      assert_match(/outside the candidate checkout/, error.message)
    end
  end

  def test_trusted_helper_rejects_symlinks_into_the_checkout
    Dir.mktmpdir('trusted-links') do |directory|
      link = File.join(directory, 'shaka')
      File.symlink(File.join(ROOT, 'skills/shaka'), link)
      linked = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: link)
      assert_raises(ArgumentError) { linked.create_command('shaka-slice0-probe-test') }
    end
  end

  def test_trusted_helper_mounts_an_external_symlink_by_its_canonical_target
    Dir.mktmpdir('trusted-target') do |target|
      FileUtils.mkdir_p(File.join(target, 'scripts'))
      write_executable(File.join(target, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
      Dir.mktmpdir('trusted-link') do |directory|
        File.symlink(target, link = File.join(directory, 'shaka'))
        command = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: link)
                                                   .create_command('shaka-slice0-probe-test')
        assert_includes command, "type=bind,src=#{File.realpath(target)},dst=/opt/shaka,readonly"
      end
    end
  end

  def test_trusted_helper_rejects_a_symlinked_entrypoint
    Dir.mktmpdir('trusted-entrypoint') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'scripts'))
      File.symlink(File.join(ROOT, 'skills/shaka/scripts/shaka'), File.join(directory, 'scripts/shaka'))
      container = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: directory)
      assert_raises(ArgumentError) { container.create_command('shaka-slice0-probe-test') }
    end
  end

  def test_trusted_helper_rejects_a_symlinked_scripts_directory
    Dir.mktmpdir('trusted-scripts') do |directory|
      File.symlink(File.join(ROOT, 'skills/shaka/scripts'), File.join(directory, 'scripts'))
      container = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: directory)
      assert_raises(ArgumentError) { container.create_command('shaka-slice0-probe-test') }
    end
  end

  def test_trusted_helper_rejects_unsafe_mount_paths
    Dir.mktmpdir('trusted,shaka') do |directory|
      FileUtils.mkdir_p(File.join(directory, 'scripts'))
      write_executable(File.join(directory, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
      unsafe = Shaka::Evaluation::ProbeContainer.new(root: ROOT, trusted_skill: directory)
      assert_raises(ArgumentError) { unsafe.create_command('shaka-slice0-probe-test') }
    end
  end
end

class LocalEvaluationProbeResetTest < Minitest::Test
  include LocalEvaluationProbeHelpers

  def test_reset_replaces_history_and_preserves_fixture_dotfiles
    script = File.join(ROOT, 'eval/docker/slice-0-probe/probe-reset')

    Dir.mktmpdir('probe-reset') do |directory|
      seed, destination = reset_fixture(directory)
      stdout, stderr, status = Open3.capture3(script, seed, destination)
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_equal %w[.ruby-version lib/color.rb], fixture_files(destination)
      assert_equal "3.4.6\n", File.read(File.join(destination, '.ruby-version'))
      assert_path_exists File.join(directory, 'tmp')
    end
  end

  private

  def reset_fixture(directory)
    seed = File.join(directory, 'seed')
    destination = File.join(directory, 'repo')
    FileUtils.mkdir_p(File.join(seed, 'lib'))
    FileUtils.mkdir_p(destination)
    File.write(File.join(seed, '.ruby-version'), "3.4.6\n")
    File.write(File.join(seed, 'lib/color.rb'), "module Color; end\n")
    File.write(File.join(destination, 'solved-history.txt'), "must disappear\n")
    [seed, destination]
  end
end

module LocalEvaluationPreflightHelpers
  private

  def with_preflight(ssh_body, stdin_data: "shakacode/private-sibling\n", environment: {}, docker_socket: nil,
                     ssh_home: false)
    Dir.mktmpdir('probe-preflight') do |directory|
      fake_bin = create_fake_tools(directory, ssh_body)
      FileUtils.mkdir_p(File.join(directory, '.ssh')) if ssh_home
      env = clean_environment(directory, fake_bin).merge(environment)
      yield(*Open3.capture3(env, *preflight_command(directory, docker_socket), stdin_data:))
    end
  end

  def create_fake_tools(directory, ssh_body)
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'gh', fake_gh)
    write_executable(fake_bin, 'git', fake_git)
    write_executable(fake_bin, 'ssh', ssh_body)
    fake_bin
  end

  def preflight_command(directory, docker_socket)
    root = LocalEvaluationProbeHelpers::ROOT
    [File.join(root, 'eval/docker/slice-0-probe/probe-preflight'),
     'shakacode/public-probe', 'shaka-eval-machine', docker_socket || File.join(directory, 'missing-docker.sock')]
  end

  def fake_gh
    <<~SH
      #!/bin/sh
      case "$*" in
        'api user --jq .login') echo "${FAKE_MACHINE_LOGIN:-shaka-eval-machine}" ;;
        'api repos/shakacode/public-probe --jq .visibility')
          [ "${FAKE_TARGET_API:-ok}" = ok ] && echo "${FAKE_TARGET_VISIBILITY:-public}" ;;
        'api repos/shakacode/private-sibling')
          [ "${FAKE_PRIVATE_API:-deny}" = allow ] && exit 0
          [ "${FAKE_PRIVATE_API:-deny}" = outage ] && echo 'gh: service unavailable (HTTP 503)' >&2 && exit 1
          echo 'gh: Not Found (HTTP 404)' >&2
          exit 1 ;;
        *) exit 2 ;;
      esac
    SH
  end

  def fake_git
    <<~SH
      #!/bin/sh
      case "$*" in
        *shakacode/public-probe.git*) [ "${FAKE_TARGET_GIT:-ok}" = ok ] ;;
        *shakacode/private-sibling.git*)
          [ "${FAKE_PRIVATE_GIT:-deny}" = allow ] && exit 0
          [ "${FAKE_PRIVATE_GIT:-deny}" = outage ] && echo 'fatal: unable to access: TLS failed' >&2 && exit 1
          echo 'remote: Repository not found.' >&2
          exit 1 ;;
        *) exit 1 ;;
      esac
    SH
  end

  def successful_ssh
    <<~SH
      #!/bin/sh
      echo 'Hi machine! You have successfully authenticated, but GitHub does not provide shell access.' >&2
      exit 1
    SH
  end

  def denied_ssh = "#!/bin/sh\necho 'Permission denied (publickey).' >&2\nexit 255\n"

  def expected_success
    <<~OUTPUT
      identity=PASS
      target=PASS
      target_https=PASS
      private_api=DENIED
      private_https=DENIED
      alternate_ssh=DENIED
      preflight=PASS
    OUTPUT
  end
end

class LocalEvaluationProbePreflightTest < Minitest::Test
  include LocalEvaluationProbeHelpers
  include LocalEvaluationPreflightHelpers

  def test_preflight_proves_the_scoped_pat_has_no_alternate_private_access
    with_preflight(denied_ssh) do |stdout, stderr, status|
      assert_predicate status, :success?, "#{stdout}\n#{stderr}"
      assert_equal expected_success, stdout
      refute_includes "#{stdout}\n#{stderr}", 'private-sibling'
    end
  end

  def test_preflight_refuses_an_available_ssh_identity
    with_preflight(successful_ssh) do |_stdout, stderr, status|
      refute_predicate status, :success?
      assert_match(/alternate GitHub SSH credential is available/, stderr)
    end
  end

  def test_preflight_accepts_private_repository_input_without_a_trailing_newline
    with_preflight(denied_ssh, stdin_data: 'shakacode/private-sibling') do |_out, err, status|
      assert_predicate status, :success?, err
    end
  end

  def test_preflight_rejects_a_malformed_private_repository
    with_preflight(denied_ssh, stdin_data: 'shakacode/one/two') do |_out, err, status|
      refute_predicate status, :success?
      assert_match(%r{private sibling repository must be OWNER/REPOSITORY}, err)
    end
  end

  def test_preflight_rejects_a_repository_with_a_backslash
    with_preflight(denied_ssh, stdin_data: 'shakacode/private\\sibling') do |_out, err, status|
      refute_predicate status, :success?
      assert_match(%r{private sibling repository must be OWNER/REPOSITORY}, err)
    end
  end

  def test_preflight_requires_a_sibling_in_the_target_owner
    with_preflight(denied_ssh, stdin_data: 'other/private-sibling') do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/same owner as the target repository/, err)
    end
  end

  def test_preflight_reports_empty_stdin
    with_preflight(denied_ssh, stdin_data: '') do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/private sibling repository is required on stdin/, err)
    end
  end

  def test_preflight_refuses_an_inconclusive_ssh_failure
    with_preflight("#!/bin/sh\necho 'Could not resolve hostname github.com' >&2\nexit 255\n") do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/GitHub SSH denial was inconclusive/, err)
    end
  end

  def test_preflight_refuses_inconclusive_private_api_failures
    with_preflight("#!/bin/sh\nexit 255\n", environment: { 'FAKE_PRIVATE_API' => 'outage' }) do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/private sibling API denial was inconclusive/, err)
    end
  end

  def test_preflight_refuses_private_access_that_succeeds
    { 'FAKE_PRIVATE_API' => 'allow', 'FAKE_PRIVATE_GIT' => 'allow' }.each do |variable, value|
      with_preflight("#!/bin/sh\nexit 255\n", environment: { variable => value }) do |_out, err, status|
        refute_predicate status, :success?
        assert_match(/can (?:read|clone) a private sibling/, err)
      end
    end
  end

  def test_preflight_rejects_inherited_credentials
    (%w[GH_TOKEN GITHUB_TOKEN SSH_AUTH_SOCK] +
      Shaka::Evaluation::PROXY_VARIABLES).each do |variable|
      with_preflight("#!/bin/sh\nexit 255\n", environment: { variable => 'present' }) do |_out, err, status|
        refute_predicate status, :success?
        assert_match(/must not be inherited/, err)
      end
    end
  end

  def test_preflight_rejects_a_mounted_docker_socket
    Dir.mktmpdir('probe-socket') do |directory|
      UNIXServer.open(socket = File.join(directory, 'docker.sock')) do
        with_preflight("#!/bin/sh\nexit 255\n", docker_socket: socket) do |_out, err, status|
          refute_predicate status, :success?
          assert_match(/Docker socket is available/, err)
        end
      end
    end
  end
end

class LocalEvaluationProbePreflightRefusalTest < Minitest::Test
  include LocalEvaluationProbeHelpers
  include LocalEvaluationPreflightHelpers

  def test_preflight_refuses_inconclusive_private_https_failures
    with_preflight("#!/bin/sh\nexit 255\n", environment: { 'FAKE_PRIVATE_GIT' => 'outage' }) do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/private sibling HTTPS denial was inconclusive/, err)
    end
  end

  def test_preflight_rejects_an_ssh_home
    with_preflight("#!/bin/sh\nexit 255\n", ssh_home: true) do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/SSH home is available/, err)
    end
  end

  def test_preflight_rejects_the_wrong_machine_identity
    environment = { 'FAKE_MACHINE_LOGIN' => 'other-machine' }
    with_preflight("#!/bin/sh\nexit 255\n", environment:) do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/not the designated machine/, err)
    end
  end

  def test_preflight_accepts_the_designated_machine_with_different_login_casing
    environment = { 'FAKE_MACHINE_LOGIN' => 'SHAKA-EVAL-MACHINE' }
    with_preflight(denied_ssh, environment:) do |_out, err, status|
      assert_predicate status, :success?, err
    end
  end

  def test_preflight_rejects_an_unavailable_target
    [{ 'FAKE_TARGET_API' => 'down' }, { 'FAKE_TARGET_GIT' => 'down' }].each do |environment|
      with_preflight("#!/bin/sh\nexit 255\n", environment:) do |_out, err, status|
        refute_predicate status, :success?
        assert_match(/target repository is unavailable/, err)
      end
    end
  end

  def test_preflight_rejects_a_nonpublic_target
    environment = { 'FAKE_TARGET_VISIBILITY' => 'private' }
    with_preflight("#!/bin/sh\nexit 255\n", environment:) do |_out, err, status|
      refute_predicate status, :success?
      assert_match(/target repository is not public/, err)
    end
  end
end

module LocalEvaluationProbeCliHelpers
  private

  def run_cleanup_wrapper(directory, docker_error)
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'docker', "#!/bin/sh\necho \"$FAKE_DOCKER_ERROR\" >&2\nexit 1\n")
    command = [File.join(LocalEvaluationProbeHelpers::ROOT, 'eval/bin/slice-0-probe-container'),
               'cleanup', 'shaka-slice0-probe-test']
    Open3.capture3(clean_environment(directory, fake_bin).merge('FAKE_DOCKER_ERROR' => docker_error), *command)
  end

  def run_terminal_auth(directory)
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'docker', fake_auth_docker)
    command = [File.join(LocalEvaluationProbeHelpers::ROOT, 'eval/bin/slice-0-probe-container'),
               'auth', 'shaka-slice0-probe-test']
    capture_pty(clean_environment(directory, fake_bin), command, 'placeholder-secret')
  end

  def run_failed_session(directory)
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'docker', failed_session_docker)
    command = [File.join(LocalEvaluationProbeHelpers::ROOT, 'eval/bin/slice-0-probe-container'),
               'session', 'shaka-slice0-probe-test', '--trusted-skill', directory]
    FileUtils.mkdir_p(File.join(directory, 'scripts'))
    write_executable(File.join(directory, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
    Open3.capture3(clean_environment(directory, fake_bin), *command)
  end

  def run_interrupted_session(directory)
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'docker', interrupted_session_docker)
    FileUtils.mkdir_p(File.join(directory, 'scripts'))
    write_executable(File.join(directory, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
    command = [File.join(LocalEvaluationProbeHelpers::ROOT, 'eval/bin/slice-0-probe-container'),
               'session', 'shaka-slice0-probe-test', '--trusted-skill', directory]
    Open3.capture3(clean_environment(directory, fake_bin), *command)
  end

  def run_ambiguous_create_session(directory, owner_failures: 0)
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'docker', ambiguous_create_docker(directory, owner_failures:))
    FileUtils.mkdir_p(File.join(directory, 'scripts'))
    write_executable(File.join(directory, 'scripts'), 'shaka', "#!/bin/sh\nexit 0\n")
    command = [File.join(LocalEvaluationProbeHelpers::ROOT, 'eval/bin/slice-0-probe-container'),
               'session', 'shaka-slice0-probe-test', '--trusted-skill', directory]
    Open3.capture3(clean_environment(directory, fake_bin), *command)
  end

  def capture_pty(environment, command, secret)
    output = +''
    reader, writer, pid = PTY.spawn(environment, *command)
    Timeout.timeout(5) { output << reader.readpartial(1024) until output.include?('Scoped PAT: ') }
    writer.puts(secret)
    read_remaining_pty(reader, output)
    Process.wait(pid)
    [output, $CHILD_STATUS]
  ensure
    writer&.close
    reader&.close
  end

  def read_remaining_pty(reader, output)
    loop { output << reader.readpartial(1024) }
  rescue EOFError, Errno::EIO
    nil
  end

  def fake_auth_docker
    <<~SH
      #!/bin/sh
      if [ "$*" = 'exec -i shaka-slice0-probe-test gh auth login --hostname github.com --with-token' ]; then
        IFS= read -r token
        [ "$token" = placeholder-secret ] || exit 3
        echo auth=PASS
        exit 0
      fi
      [ "$*" = 'exec shaka-slice0-probe-test gh auth setup-git' ]
    SH
  end

  def failed_session_docker
    <<~SH
      #!/bin/sh
      case "$*" in
        'container inspect '*) exit 1 ;;
        'start '*) echo 'start failed' >&2; exit 1 ;;
        'rm --force --volumes '*) echo 'cleanup failed too' >&2; exit 1 ;;
        *) exit 0 ;;
      esac
    SH
  end

  def interrupted_session_docker
    <<~SH
      #!/bin/sh
      case "$*" in
        'container inspect '*) exit 1 ;;
        'start '*) kill -INT "$PPID"; sleep 0.1; exit 1 ;;
        'rm --force --volumes '*) echo 'cleanup failed too' >&2; exit 1 ;;
        *) exit 0 ;;
      esac
    SH
  end
end

module LocalEvaluationAmbiguousCreateHelpers
  private

  def ambiguous_create_docker(directory, owner_failures:)
    <<~SH
      #!/bin/sh
      owner_file=#{File.join(directory, 'owner')}
      attempts_file=#{File.join(directory, 'attempts')}
      case "$1 $2" in
        'container inspect')
          if [ "${3:-}" = --format ]; then
            attempts=0
            [ ! -f "$attempts_file" ] || attempts=$(cat "$attempts_file")
            attempts=$((attempts + 1))
            printf '%s\n' "$attempts" > "$attempts_file"
            [ "$attempts" -le #{owner_failures} ] && exit 1
            cat "$owner_file"
            exit 0
          fi
          exit 1 ;;
        'build --tag') exit 0 ;;
        'create --name')
          while [ "$#" -gt 0 ]; do
            [ "$1" = --label ] && shift && printf '%s\n' "${1#*=}" > "$owner_file" && exit 1
            shift
          done
          exit 2 ;;
        'rm --force') touch #{File.join(directory, 'cleaned')}; exit 0 ;;
        *) exit 2 ;;
      esac
    SH
  end
end

class LocalEvaluationProbeCliTest < Minitest::Test
  include LocalEvaluationProbeHelpers
  include LocalEvaluationProbeCliHelpers
  include LocalEvaluationAmbiguousCreateHelpers

  def test_preflight_wrapper_accepts_rest_private_visibility_and_streams_the_sibling
    Dir.mktmpdir('probe-cli') do |directory|
      stdout, stderr, status = run_preflight_wrapper(directory)
      assert_predicate status, :success?, stderr
      assert_equal "wrapper=PASS\n", stdout
    end
  end

  def test_preflight_wrapper_refuses_machine_owner_or_nonprivate_sibling
    [{ 'FAKE_OWNER_LOGIN' => 'shaka-eval-machine' }, { 'FAKE_OWNER_LOGIN' => 'SHAKA-EVAL-MACHINE' },
     { 'FAKE_VISIBILITY' => 'public' }].each do |environment|
      Dir.mktmpdir('probe-cli') do |directory|
        _stdout, stderr, status = run_preflight_wrapper(directory, environment:)
        refute_predicate status, :success?
        assert_match(/must differ|could not verify/, stderr)
      end
    end
  end

  def test_preflight_wrapper_refuses_an_outside_collaborator
    Dir.mktmpdir('probe-cli') do |directory|
      _stdout, stderr, status = run_preflight_wrapper(directory, environment: { 'FAKE_MEMBERSHIP' => 'outside' })
      refute_predicate status, :success?
      assert_match(/organization membership/, stderr)
    end
  end

  def test_cleanup_reports_removal_failure
    Dir.mktmpdir('probe-cleanup') do |directory|
      _out, error, failed = run_cleanup_wrapper(directory, 'daemon unavailable')
      refute_predicate failed, :success?
      assert_match(/cleanup failed/, error)
    end
  end

  def test_cleanup_accepts_an_absent_container
    Dir.mktmpdir('probe-cleanup') do |directory|
      _out, error, absent = run_cleanup_wrapper(directory, 'No such container: test')
      assert_predicate absent, :success?, error
    end
  end

  def test_auth_hides_a_pat_typed_at_a_terminal
    Dir.mktmpdir('probe-auth') do |directory|
      output, status = run_terminal_auth(directory)
      assert_predicate status, :success?, output
      assert_includes output, 'auth=PASS'
      refute_includes output, 'placeholder-secret'
    end
  end

  private

  def run_preflight_wrapper(directory, environment: {})
    fake_bin = File.join(directory, 'bin')
    FileUtils.mkdir_p(fake_bin)
    write_executable(fake_bin, 'gh', owner_gh)
    write_executable(fake_bin, 'docker', docker_preflight)
    command = [File.join(ROOT, 'eval/bin/slice-0-probe-container'), 'preflight',
               'shaka-slice0-probe-test', 'shakacode/public-probe', 'shaka-eval-machine']
    Open3.capture3(clean_environment(directory, fake_bin).merge(environment), *command,
                   stdin_data: "shakacode/private-sibling\n")
  end

  def owner_gh
    <<~SH
      #!/bin/sh
      [ "$*" = 'api user --jq .login' ] && echo "${FAKE_OWNER_LOGIN:-justin808}" && exit 0
      [ "$*" = 'api repos/shakacode/private-sibling --jq .visibility' ] && echo "${FAKE_VISIBILITY:-private}" && exit 0
      [ "$*" = 'api orgs/shakacode/members/shaka-eval-machine --silent' ] && [ "${FAKE_MEMBERSHIP:-member}" = member ] && exit 0
      exit 2
    SH
  end

  def docker_preflight
    <<~SH
      #!/bin/sh
      [ "$*" = 'exec -i shaka-slice0-probe-test probe-preflight shakacode/public-probe shaka-eval-machine' ] || exit 4
      IFS= read -r repository
      [ "$repository" = shakacode/private-sibling ] || exit 3
      echo wrapper=PASS
    SH
  end
end

class LocalEvaluationProbeSessionCliTest < Minitest::Test
  include LocalEvaluationProbeHelpers
  include LocalEvaluationProbeCliHelpers
  include LocalEvaluationAmbiguousCreateHelpers

  def test_session_reports_operation_and_cleanup_failures
    Dir.mktmpdir('probe-session') do |directory|
      _output, error, status = run_failed_session(directory)
      refute_predicate status, :success?
      assert_match(/Container cleanup failed: cleanup failed too/, error)
      assert_match(/Command failed: docker start/, error)
    end
  end

  def test_session_preserves_an_interrupt_when_cleanup_fails
    Dir.mktmpdir('probe-session') do |directory|
      _output, error, status = run_interrupted_session(directory)
      refute_predicate status, :success?
      assert_match(/Container cleanup failed: cleanup failed too/, error)
      assert_match(/Interrupt/, error)
    end
  end

  def test_session_cleans_a_container_created_before_an_ambiguous_client_failure
    Dir.mktmpdir('probe-session') do |directory|
      _output, error, status = run_ambiguous_create_session(directory, owner_failures: 1)
      refute_predicate status, :success?
      assert_match(/Command failed: docker create/, error)
      assert_path_exists File.join(directory, 'cleaned')
    end
  end

  def test_session_reports_when_ownership_cannot_be_reconciled
    Dir.mktmpdir('probe-session') do |directory|
      _output, error, status = run_ambiguous_create_session(directory, owner_failures: 3)
      refute_predicate status, :success?
      assert_match(/ownership could not be reconciled; manual cleanup may be required/, error)
      refute_path_exists File.join(directory, 'cleaned')
    end
  end
end
