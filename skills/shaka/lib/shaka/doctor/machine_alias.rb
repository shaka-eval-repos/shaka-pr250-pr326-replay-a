# frozen_string_literal: true

require 'socket'
require_relative '../publication/provenance'
require_relative 'check'

module Shaka
  class Doctor
    # Reports whether this machine has an alias fit to publish.
    #
    # Publication accepts any value matching its safe-value pattern, and a real host name
    # matches it. So this check, not the renderer, is what stands between the machine's own
    # name and every public pull request it would appear in.
    class MachineAlias
      include Check

      VARIABLE = 'SHAKA_MACHINE_ALIAS'
      HOST_NAMES = %w[HOST HOSTNAME].freeze
      EXAMPLES = %w[m5 m1 lab1].freeze

      def initialize(environment, host_name: self.class.system_name)
        @environment = environment
        @host_name = host_name
      end

      # A shell exports HOST and HOSTNAME inconsistently, and usually not to a command like
      # this one, so the system's own answer is what makes this guard actually fire.
      def self.system_name
        Socket.gethostname
      rescue StandardError
        nil
      end

      def call
        value = @environment[VARIABLE]
        return unset if value.nil? || value.empty?
        return unpublishable unless valid?(value)
        return host_name if host_name?(value)
        return unverified_alias if candidates.empty?

        check('Machine alias', 'healthy', "provenance will publish #{value}")
      end

      private

      def unset
        check('Machine alias', 'degraded', "#{VARIABLE} is unset; provenance will read UNKNOWN", guidance: guidance)
      end

      def unpublishable
        check('Machine alias', 'failed', "#{VARIABLE} is set to a value publication refuses", guidance: guidance)
      end

      # A machine may well be called `m5`, and suggesting its own name is the one thing this
      # check exists to prevent, so the example is checked against the machine like any value.
      def guidance
        example = EXAMPLES.find { |token| !host_name?(token) }
        suggestion = example ? "a short deliberate token such as `#{example}`" : 'a short deliberate token'
        "Export #{VARIABLE} as #{suggestion}. It appears in public pull requests, so do not use " \
          "this machine's own name."
      end

      # Without this machine's name there is nothing to compare against, so the guard did not
      # run. Reporting healthy would claim a check that never happened.
      def unverified_alias
        check('Machine alias', 'degraded', 'this machine has no name to compare the alias against',
              guidance: "Confirm #{VARIABLE} is not this machine's own name; it appears in public " \
                        'pull requests.')
      end

      # Degrades rather than blocks: the value publishes, and whether to publish it is the user's.
      # The name itself stays out of the report.
      def host_name
        check('Machine alias', 'degraded', "#{VARIABLE} is this machine's own name",
              guidance: 'Publication would put your machine name in every public pull request. ' \
                        "Replace it: #{guidance}")
      end

      def host_name?(value)
        candidates.any? { |name| name.casecmp?(value) }
      end

      # The bare name counts too: `build-host` is as identifying as `build-host.local`.
      # Blank names are dropped first: "".split('.') is empty, and its .first is nil.
      def candidates
        names = (HOST_NAMES.map { |name| @environment[name] } + [@host_name]).reject { |n| n.to_s.empty? }
        names.flat_map { |name| [name, name.split('.').first] }.compact.uniq
      end

      def valid?(value) = ExecutionProvenance::SAFE_VALUE.match?(value)
    end
  end
end
