# frozen_string_literal: true

require_relative 'error'

module Shaka
  # Refuses a merge unless every gating check (native, or seam-declared as a fallback) is passing.
  module MergeRequiredChecks
    EMPTY_REQUIRED_CHECKS = 'GitHub reported no required checks on this branch. Merge refuses that empty set. ' \
                            'If the branch is unprotected, enable branch protection or list merge.required_checks; ' \
                            'if required checks have not registered yet, wait and retry. This is not unread evidence.'

    private

    def verify_checks(checks)
      raise Error, 'No observable required checks; native readiness is unknown' unless checks.is_a?(Array)
      raise Error, EMPTY_REQUIRED_CHECKS if checks.empty?

      checks.each do |check|
        next if passing_check?(check)

        raise Error, "Required check is not passing or is malformed: #{check.inspect}"
      end
    end

    def passing_check?(check)
      return false unless check.is_a?(Hash) && check['name'].is_a?(String) && !check['name'].strip.empty?

      case check['state']
      when 'SUCCESS' then check['bucket'] == 'pass'
      when 'NEUTRAL', 'SKIPPED' then check['bucket'] == 'skipping'
      else false
      end
    end
  end
end
