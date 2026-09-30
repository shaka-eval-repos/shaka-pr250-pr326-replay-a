# frozen_string_literal: true

require_relative 'check'

module Shaka
  class Doctor
    # Locates an openable session source; it does not parse usage records.
    class UsageSourceCheck
      include Check

      def initialize(host:, system:)
        @host = host
        @system = system
      end

      # discover locates sources; it never opens them. Only a file this command can read is
      # evidence, so a session handle it cannot open is reported as located, not as ready.
      def call
        return incomplete('the host is ambiguous') if @host.nil?

        locate
      rescue KeyError, SystemCallError => e
        shortfall(first_line(e.message), unopened: true)
      end

      private

      def locate
        located = @system.usage_source.call(@host)
        unopened = located.reject { |entry| openable?(entry) }
        return shortfall(gap(located, unopened), unopened: unopened.any?) if located.empty? || unopened.any?
        return missing("#{located.length} openable #{@host} source(s)") if @host == 'cursor' && !hook?

        check('Usage source', 'healthy', "#{located.length} openable #{@host} source(s); " \
                                         'doctor does not parse them')
      end

      # A readable directory, FIFO, or device is not a transcript, and an empty file carries
      # no responses, so neither is evidence that usage will have anything to report.
      def openable?(entry)
        path = entry.to_s
        File.file?(path) && File.readable?(path) && !File.empty?(path)
      end

      def gap(located, unopened)
        return "no #{@host} session source" if located.empty?

        "#{unopened.length} of #{located.length} #{@host} sources cannot be opened here"
      end

      def shortfall(reason, unopened:)
        return incomplete(reason) unless @host == 'cursor'
        return missing(reason) unless hook?
        return unread(reason) if unopened

        pending(reason)
      end

      def hook?
        probe = @system.cursor_stop_hook
        probe.respond_to?(:call) && probe.call
      end

      def missing(reason)
        failure(reason, 'Install the Cursor stop hook from the getting-started guide, start a new ' \
                        'Agent chat, and confirm `shaka usage` can open a stop-hook file for this ' \
                        'conversation.')
      end

      def unread(reason)
        failure(reason, 'The Cursor stop hook is installed, but a located usage file cannot be ' \
                        'opened here. Confirm the file for this conversation is readable.')
      end

      def failure(reason, guidance)
        check('Usage source', 'failed', "#{reason}; Cursor stop-hook usage is not readable", guidance: guidance)
      end

      def pending(reason)
        check('Usage source', 'degraded', "#{reason}; Cursor stop-hook usage is not readable yet",
              guidance: 'Expected until the first Cursor stop event for this chat. Refresh ' \
                        '`shaka usage` after stop. Install the hook from the getting-started ' \
                        'guide only if doctor still fails.')
      end

      def incomplete(reason)
        check('Usage source', 'degraded', "#{reason}; usage may be incomplete",
              guidance: 'Pass `--host` to name the host, and `--file` to `shaka usage` when its ' \
                        'session source is not a file this command can read.')
      end
    end
  end
end
