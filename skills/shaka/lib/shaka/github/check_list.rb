# frozen_string_literal: true

module Shaka
  class GitHub
    # Reads `gh pr checks`, including the unprotected empty-list diagnostic.
    module CheckList
      CHECK_EXITS = [0, 1, 8].freeze
      NO_CHECKS = /\Ano checks reported on the '[^\r\n]+' branch(?:\r?\n)?\z/
      NO_REQUIRED_CHECKS = /\Ano required checks reported on the '[^\r\n]+' branch(?:\r?\n)?\z/

      def checks(required: false)
        stdout, stderr = fetch_check_streams(required)
        return [] if stdout.strip.empty? && empty_check_list?(stderr, required)

        result = parse_json(stdout)
        raise Error, 'GitHub checks response must be an array.' unless result.is_a?(Array)

        result
      end

      def required_checks
        checks(required: true)
      rescue Error
        raise Error, 'Required-check evidence is unavailable; confirm native required checks and GitHub access.'
      end

      private

      def fetch_check_streams(required)
        argv = ['gh', 'pr', 'checks', @number.to_s, '--repo', @repository]
        argv << '--required' if required
        argv.push('--json', 'name,state,bucket,link')
        stdout, stderr, status = @runner.call(argv, stdin_data: '')
        unless CHECK_EXITS.include?(status.exitstatus)
          raise Error.from_gh("gh pr #{@number} failed (exit #{status.exitstatus}).", stderr)
        end

        [utf8(stdout), utf8(stderr)]
      rescue Errno::ENOENT
        raise Error, 'GitHub CLI is unavailable; install gh and authenticate.'
      end

      def empty_check_list?(stderr, required)
        stderr.match?(NO_CHECKS) || (required && stderr.match?(NO_REQUIRED_CHECKS))
      end
    end
  end
end
