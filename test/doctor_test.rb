# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'doctor_helper'

class DoctorTest < Minitest::Test
  include DoctorHelper

  def test_a_ready_environment_reports_healthy_and_does_not_block
    report, blocked = doctor
    assert_includes report, 'HEALTHY'
    refute_includes report, 'FAILED'
    refute_includes report, 'DEGRADED'
    refute blocked
  end

  def test_installation_json_rejects_repository_and_host_flags
    [%w[--root /repo], %w[--host codex]].each do |flags|
      _output, error = capture_io do
        assert_equal 1, Shaka::Doctor.run(['--installation-json', *flags])
      end
      assert_includes error, 'cannot be combined'
    end
  end

  def test_an_unset_alias_degrades_the_report_without_blocking
    report, blocked = doctor(environment: {})
    assert_includes report, 'DEGRADED'
    assert_includes report, 'UNKNOWN'
    refute blocked
  end

  # The alias is published on public pull requests, so doctor must never point at the machine's name.
  def test_alias_guidance_never_offers_a_host_name
    host = 'developer-laptop-m5-max'
    report, = doctor(environment: { 'HOST' => host, 'HOSTNAME' => host })
    assert_includes report, 'DEGRADED'
    refute_includes report, host
  end

  # A value the publication renderer would reject blocks now instead of failing mid-publication.
  def test_an_unpublishable_alias_blocks
    report, blocked = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => 'customer machine' })
    assert_includes report, 'FAILED'
    assert blocked
    refute_includes report, 'customer machine'
  end

  # Publication accepts a host name, so doctor is the only thing standing between the
  # machine's own name and every public pull request it would appear in.
  def test_an_alias_set_to_the_machine_name_is_flagged_without_republishing_it
    name = 'developer-laptop-m5-max'
    report, blocked = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => name, 'HOSTNAME' => name })
    assert_includes report, 'DEGRADED'
    refute_includes report, name
    refute blocked
  end

  def test_an_alias_matching_the_host_name_in_another_case_is_still_flagged
    report, = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => 'Build-Host', 'HOST' => 'build-host' })
    assert_includes report, 'DEGRADED'
  end

  # HOST and HOSTNAME are shell variables a command like this usually does not receive,
  # so the guard has to ask the system for its own name or it never fires in practice.
  def test_the_system_host_name_is_caught_without_any_host_variable
    report, = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => 'test-machine.local' })
    assert_includes report, 'DEGRADED'
  end

  # A machine really can be called `m5`, and suggesting its own name back to it is the one
  # thing this check exists to prevent.
  def test_the_suggested_example_is_never_this_machine_name
    %w[m5 m5.local].each do |name|
      report, = doctor(host_name: name, environment: {})
      assert_includes report, 'DEGRADED', name
      refute_match(/`m5`/, report, name)
    end
  end

  # An exported-but-empty HOST used to crash the whole command instead of reporting anything.
  def test_a_blank_host_variable_does_not_abort_the_report
    report, blocked = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => 'm5', 'HOST' => '', 'HOSTNAME' => '' })
    assert_includes report, 'Machine alias'
    refute blocked
  end

  def test_the_suggestion_is_dropped_when_every_example_collides
    report, = doctor(host_name: 'lab1', environment: { 'HOST' => 'm5', 'HOSTNAME' => 'm1' })
    assert_includes report, 'a short deliberate token.'
  end

  # `build-host` identifies the machine exactly as much as `build-host.local` does.
  def test_the_bare_form_of_a_dotted_host_name_is_caught
    report, = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => 'test-machine' })
    assert_includes report, 'DEGRADED'
  end

  def test_a_deliberate_alias_is_healthy_even_when_a_host_name_is_present
    report, blocked = doctor(environment: { 'SHAKA_MACHINE_ALIAS' => 'm5', 'HOST' => 'build-host' })
    refute_includes report, 'DEGRADED'
    refute blocked
  end

  # Without a name to compare against, the hostname guard did not run, and saying healthy
  # would claim a check that never happened.
  def test_an_alias_is_not_healthy_when_this_machine_has_no_name
    report, blocked = doctor(host_name: nil, environment: { 'SHAKA_MACHINE_ALIAS' => 'm5' })
    assert_includes report, 'DEGRADED'
    refute blocked
  end

  # One pass: a blocking failure must not hide the checks after it.
  def test_every_check_is_reported_even_when_one_fails
    ready, = doctor
    broken, = doctor(environment: {}, responses: { view: ['', 'gh auth login required', false] })
    assert_equal check_names(ready), check_names(broken)
    assert_equal 6, check_names(broken).length
  end

  def test_the_worst_status_is_reported_first
    report, = doctor(environment: {}, responses: { view: ['', 'gh auth login required', false] })
    statuses = report.scan(/^\[(\w+)\]/).flatten
    assert_equal statuses.sort_by { |status| -Shaka::Doctor::SEVERITY.fetch(status.downcase) }, statuses
  end
end
