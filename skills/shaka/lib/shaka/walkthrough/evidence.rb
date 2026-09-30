# frozen_string_literal: true

require 'uri'
require_relative '../error'
require_relative '../required_checks'
require_relative '../public_comments/bounded_list'

module Shaka
  # Refuses a walkthrough that does not cite live diff and check evidence.
  class WalkthroughEvidence
    FILE_PAGES = 10
    TERMINAL_BUCKETS = %w[pass fail skipping cancel].freeze

    def initialize(github, seam_required_checks: nil)
      @github = github
      @seam_required_checks = seam_required_checks
    end

    def verify(head, body)
      verify_commit_pin(head, body)
      verify_gates(body)
    end

    private

    def verify_commit_pin(head, body)
      paths = changed_paths
      return if pinned_paths(body, head).intersect?(paths)

      raise Error, 'Walkthrough requires a commit-pinned link to a changed file.'
    end

    def changed_paths
      path = "repos/#{@github.repository}/pulls/#{@github.number}/files"
      files = PublicComments::BoundedList.new(@github, max_pages: FILE_PAGES, label: 'Walkthrough file list').call(path)
      files.flat_map { |file| [file['filename'], file['previous_filename']].compact }
    end

    def pinned_paths(body, head)
      prefix = blob_url(head, '')
      body.to_enum(:scan, /#{Regexp.escape(prefix)}([^\s)#<>]+)/).map do
        URI.decode_uri_component(Regexp.last_match(1)).sub(/[.,;:!?]+$/, '')
      end
    end

    def blob_url(head, path) = "https://github.com/#{@github.repository}/blob/#{head}/#{path}"

    def verify_gates(body)
      missing = gate_names.reject { |name| named_gate?(body, name) }
      return if missing.empty?

      raise Error, "Walkthrough omits completed gates: #{missing.join(', ')}."
    end

    def gate_names
      (completed_names(required_rows) + review_names).uniq
    end

    def required_rows = RequiredChecks.new(@github, seam_names: @seam_required_checks).call.fetch('checks')

    def named_gate?(body, name)
      body.match?(/(?<![A-Za-z0-9_-])#{Regexp.escape(name)}(?![A-Za-z0-9_-])/)
    end

    def review_names
      completed_names(@github.checks).grep(/review/i)
    end

    def completed_names(rows)
      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        name = row['name']
        next unless name.is_a?(String) && !name.empty?
        next unless TERMINAL_BUCKETS.include?(row['bucket'].to_s)

        name
      end
    end
  end
end
