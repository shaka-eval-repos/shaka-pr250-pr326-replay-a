# frozen_string_literal: true

module Shaka
  # Chooses the checks that gate a PR. GitHub's native required checks win; the trusted
  # seam's merge.required_checks applies only when GitHub enforces none, as on a private
  # repository whose plan offers no branch protection.
  class RequiredChecks
    def initialize(github, seam_names: nil)
      @github = github
      @seam_names = seam_names
    end

    def call
      native = @github.required_checks
      return github(native) unless native == []

      # An empty report only means no required check has reported yet; configured ones still gate.
      configured = @github.configured_required_checks
      return github(configured.map { |name| missing(name) }) unless configured.empty?
      return github([]) unless @seam_names&.any?

      { 'source' => 'seam', 'checks' => seam_rows }
    end

    private

    def github(checks) = { 'source' => 'github', 'checks' => checks }

    def missing(name) = { 'name' => name, 'state' => 'MISSING', 'bucket' => 'missing' }

    # A declared check that never reported on the head must block, so a renamed or removed
    # job fails closed instead of silently dropping out of the gate.
    def seam_rows
      head = @github.checks
      @seam_names.flat_map do |name|
        rows = head.select { |row| row.is_a?(Hash) && row['name'] == name }
        rows.empty? ? [missing(name)] : rows
      end
    end
  end
end
