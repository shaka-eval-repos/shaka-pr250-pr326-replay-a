# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'shaka/doctor/cursor_stop_hook'

# Doctor must fail a missing stop command, not a missing this-chat usage file.
class CursorStopHookTest < Minitest::Test
  HOOK = { 'command' => 'skills/shaka/scripts/cursor-usage-hook' }.freeze

  # Break: treating an afterAgentResponse-only command as installed would pass doctor
  # while persist() still drops those payloads.
  def test_a_stop_array_command_is_installed
    with_hooks('afterAgentResponse' => [HOOK]) { |path| refute installed?(path) }
    with_hooks('stop' => [HOOK]) { |path| assert installed?(path) }
  end

  def test_a_missing_or_invalid_file_is_not_installed
    refute installed?('/definitely/missing/hooks.json')
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'hooks.json')
      File.write(path, '{')
      refute installed?(path)
    end
  end

  # Break: a numeric command kept by filter_map makes include? raise NoMethodError out of doctor.
  def test_a_non_string_stop_command_is_not_installed
    with_hooks('stop' => [{ 'command' => 1 }]) { |path| refute installed?(path) }
  end

  # Break: include? treats `echo cursor-usage-hook` as the persistence script.
  def test_a_command_that_only_mentions_the_hook_name_is_not_installed
    with_hooks('stop' => [{ 'command' => 'echo cursor-usage-hook' }]) { |path| refute installed?(path) }
  end

  # Break: File.basename raises ArgumentError on a null byte, and that escapes installed?.
  def test_a_null_byte_in_a_stop_command_is_not_installed
    with_hooks('stop' => [{ 'command' => "\0cursor-usage-hook" }]) { |path| refute installed?(path) }
  end

  # Break: expanding ~/hooks.json at load or as a default argument raises ArgumentError
  # when HOME cannot be resolved, and Doctor.run does not rescue that for other hosts.
  def test_an_unresolvable_home_is_not_installed
    original = File.method(:expand_path)
    File.define_singleton_method(:expand_path) do |*|
      raise ArgumentError, "couldn't find HOME environment"
    end
    refute_predicate(Shaka::Doctor::CursorStopHook, :installed?)
  ensure
    File.define_singleton_method(:expand_path, original)
  end

  private

  def installed?(path)
    Shaka::Doctor::CursorStopHook.installed?(path)
  end

  def with_hooks(events)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'hooks.json')
      File.write(path, JSON.generate('version' => 1, 'hooks' => events))
      yield path
    end
  end
end
