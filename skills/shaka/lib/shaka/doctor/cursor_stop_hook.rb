# frozen_string_literal: true

require 'json'

module Shaka
  class Doctor
    # Reads user-level Cursor hooks.json for the stop-hook command; never reads usage payloads.
    class CursorStopHook
      NAME = 'cursor-usage-hook'
      HOOKS = '~/.cursor/hooks.json'

      def self.installed?(path = nil)
        new(path || File.expand_path(HOOKS)).installed?
      rescue ArgumentError
        false
      end

      def initialize(path)
        @path = path
      end

      def installed?
        commands.any? { |command| hook_command?(command) }
      rescue SystemCallError, JSON::ParserError
        false
      end

      private

      def commands
        parsed = JSON.parse(File.read(@path, encoding: 'UTF-8'))
        hooks = parsed['hooks'] if parsed.is_a?(Hash)
        stop = hooks['stop'] if hooks.is_a?(Hash)
        Array(stop).filter_map { |entry| command_text(entry) }
      end

      def command_text(entry)
        value = entry['command'] if entry.is_a?(Hash)
        value if value.is_a?(String)
      end

      def hook_command?(command)
        token = command.split.first
        File.basename(token.to_s) == NAME
      rescue ArgumentError
        false
      end
    end
  end
end
