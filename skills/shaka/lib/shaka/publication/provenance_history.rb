# frozen_string_literal: true

require 'json'
require_relative '../error'
require_relative '../usage/records'
require_relative 'provenance'

module Shaka
  # Keeps one entry per change of workflow commit or route across a PR's publications, since
  # the provenance table shows only the latest. Entries live in a hidden marker from the first
  # publication, so the head of the original route is known when it first changes.
  module ProvenanceHistory
    PREFIX = '<!-- shaka:provenance '
    MARK = /#{Regexp.escape(PREFIX)}(.*?) -->/
    SUMMARY = 'Provenance history'
    FIELDS = %w[head workflow requested recommended active].freeze
    ROUTES = %w[requested recommended active].freeze
    # The entries after the first that a long-lived PR keeps.
    RECENT = 20
    HEAD = /\A\h{40}\z/
    # The three shapes WorkflowVersion::Result#markdown renders.
    WORKFLOW = %r{\A(?:\[`\h{7}`\]\(https://github\.com/shakacode/shaka/commit/(?:\h{40}|\h{64})\)(?:\ \(modified\))?|
                  `(?:\h{40}|\h{64})`(?:\ \(modified\))?|
                  `[A-Za-z0-9][A-Za-z0-9._+-]*`\ \(commit\ unknown(?:,\ modified)?\))\z}x

    module_function

    # A fork author can edit the body, so a fork's history is never carried, as with usage.
    def carry(pull, current)
      entry = current.merge('head' => head(pull))
      history = same_repository?(pull) ? previous(pull['body']) : fresh
      entries = history.fetch('entries')
      return history if entries.any? && changes(entries.last) == changes(entry)

      bounded(entries + [entry], history.fetch('omitted'))
    end

    def marker(history) = "#{PREFIX}#{JSON.generate(history)} -->"

    # A PR whose provenance never changed keeps its single table.
    def detail(history)
      entries = history.fetch('entries')
      return if entries.size < 2

      { 'summary' => SUMMARY, 'body' => [omission(history.fetch('omitted')), table(entries)].compact.join("\n\n") }
    end

    def head(pull)
      sha = pull.dig('head', 'sha')
      raise Error, 'Pull request head commit is unavailable for provenance history.' unless sha.to_s.match?(HEAD)

      sha
    end

    def same_repository?(pull)
      repository = pull.dig('head', 'repo', 'full_name')
      repository && repository == pull.dig('base', 'repo', 'full_name')
    end

    # A body published before this history existed starts a new one; a damaged history is
    # refused rather than rewritten, so no recorded entry disappears unnoticed.
    def previous(body)
      region = UsageRecords.managed_region(body).to_s
      # Any opening counts, so a marker damaged past matching is refused rather than restarted.
      openings = region.scan(PREFIX.strip).size
      return fresh if openings.zero?

      json = region[MARK, 1]
      raise invalid unless openings == 1 && json

      validated(JSON.parse(json))
    rescue JSON::ParserError
      raise invalid
    end

    def fresh = { 'entries' => [], 'omitted' => 0 }

    def validated(history)
      valid = history.is_a?(Hash) && history.keys.sort == %w[entries omitted] &&
              history['omitted'].is_a?(Integer) && !history['omitted'].negative? && valid_entries?(history['entries'])
      raise invalid unless valid

      history
    end

    def valid_entries?(entries)
      entries.is_a?(Array) && entries.size.between?(1, RECENT + 1) && entries.all? { |entry| valid_entry?(entry) }
    end

    def valid_entry?(entry)
      entry.is_a?(Hash) && entry.keys.sort == FIELDS.sort && entry.values.all?(String) &&
        entry['head'].match?(HEAD) && entry['workflow'].match?(WORKFLOW) &&
        ROUTES.all? { |route| valid_route?(entry[route]) }
    end

    # A route renders as `model / effort`, each an allowlisted provenance value.
    def valid_route?(route)
      parts = route.split(' / ', -1)
      parts.size == 2 && parts.all? { |part| part.match?(ExecutionProvenance::SAFE_VALUE) }
    end

    def invalid
      Error.new('The PR body holds a provenance history this helper did not write; ' \
                "restore or remove its #{PREFIX.strip} marker, then publish again.")
    end

    def changes(entry) = entry.except('head')

    def bounded(entries, omitted)
      extra = entries.size - (RECENT + 1)
      return { 'entries' => entries, 'omitted' => omitted } unless extra.positive?

      { 'entries' => [entries.first, *entries.last(RECENT)], 'omitted' => omitted + extra }
    end

    def omission(omitted)
      return if omitted.zero?

      "#{omitted} #{omitted == 1 ? 'entry' : 'entries'} after the first #{omitted == 1 ? 'is' : 'are'} omitted."
    end

    def table(entries)
      rows = entries.map do |entry|
        "| `#{entry['head'][0, 7]}` | #{entry['workflow']} | #{ROUTES.map { |route| entry[route] }.join(' | ')} |"
      end
      ['| Head | Workflow version | Requested route | Recommended route | Active setting |',
       '| --- | --- | --- | --- | --- |', *rows].join("\n")
    end

    private_class_method :head, :same_repository?, :previous, :fresh, :validated, :valid_entries?, :valid_entry?,
                         :valid_route?, :invalid, :changes, :bounded, :omission, :table
  end
end
