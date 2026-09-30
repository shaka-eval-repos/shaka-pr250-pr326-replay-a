# frozen_string_literal: true

require_relative '../reviewer_selection'
require_relative 'evidence'

module Shaka
  # Classifies a host-produced report without claiming the CLI was launched.
  class LocalReviewReportCheck
    def initialize(options) = @options = options

    def run
      head = @options[:head]
      validate_head!(head)

      report = @options[:report]
      reason = @options[:not_run_reason]
      raise Shaka::Error, 'Supply either --report or --not-run-reason, not both' if report && reason

      return report_result(report, head) if report

      unreported_result(head, reason)
    rescue Shaka::Error, SystemCallError, KeyError => e
      { 'status' => 'not_completed', 'head' => @options[:head], 'reason' => e.message,
        'same_model_fallback_available' => true }
    end

    private

    def validate_head!(head)
      raise Shaka::Error, '--head must be a full commit SHA' unless head.to_s.match?(LocalReviewEvidence::SHA)
    end

    def unreported_result(head, reason)
      raise Shaka::Error, '--not-run-reason is required when no report exists' if reason.to_s.strip.empty?

      { 'status' => 'not_completed', 'head' => head, 'reason' => reason.strip,
        'same_model_fallback_available' => true }
    end

    def report_result(path, head)
      return missing_reviewer(head) if @options[:reviewer].to_s.empty?

      reviewer = ReviewerSelection.parse(@options.fetch(:reviewer)).values.map(&:downcase).join('/')
      text = File.read(path, encoding: 'UTF-8')
      unless LocalReviewEvidence.valid?(text, head:, reviewer:)
        return { 'status' => 'not_completed', 'head' => head,
                 'reason' => 'Report has no matching current-head review attestation',
                 'same_model_fallback_available' => true }
      end

      { 'status' => 'reported', 'head' => head, 'reviewer' => reviewer,
        'evidence' => 'host_report', 'cli_invocation_verified' => false, 'report' => path }
    end

    def missing_reviewer(head)
      { 'status' => 'not_completed', 'head' => head,
        'reason' => '--reviewer is required with --report', 'same_model_fallback_available' => true }
    end
  end
end
