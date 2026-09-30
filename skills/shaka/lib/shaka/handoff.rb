# frozen_string_literal: true

require_relative 'attention'
require_relative 'error'
require_relative 'merge_required_checks'
require_relative 'status'
require_relative 'handoff/squash_note'
require_relative 'handoff/walkthrough'
require_relative 'handoff/wip_note'

module Shaka
  # Reports what an agent still owes a PR before it ends a turn, and what a resumed session finds.
  # It reads only; the agent settles each owed item and runs it again.
  class Handoff
    include MergeRequiredChecks

    OWED_EXIT = 2
    SHORT = 7

    # A Stop hook or script can refuse to end the turn on this status without parsing the report.
    def self.exit_status(result) = result.fetch('owed').empty? ? 0 : OWED_EXIT

    def initialize(github, seam_required_checks: nil)
      @github = github
      @status = Status.new(github, seam_required_checks:)
    end

    # woken_by names what will wake this session, such as a host PR monitor or a background watcher;
    # the PR then needs no attention label, because the agent, not a person, acts next.
    def call(head: nil, woken_by: nil)
      @woken_by = wake_source(woken_by)
      pr = @status.call
      live = pr.fetch('headRefOid')
      @owed = []
      @notes = []
      @labels = []
      @owed << "PR head moved to #{live}; reread the PR before stopping." if head && head != live
      facts = pr['state'] == 'OPEN' ? open_facts(pr, live) : []
      { 'status' => ["PR ##{@github.number} #{pr['state']} head #{live[0, SHORT]}", *facts].join(' · '),
        'owed' => @owed, 'notes' => @notes, 'head' => live, 'state' => pr['state'] }
    end

    private

    # A blank name, as from an unset variable in a wrapper, would silently excuse a missing label.
    def wake_source(name)
      return if name.nil?
      raise Error, '--woken-by needs a name for what will wake this session.' if name.strip.empty?

      name.strip
    end

    def open_facts(snapshot, live)
      checks = snapshot['requiredChecks']
      [label_fact(checks), checks_fact(checks, snapshot['requiredChecksUnavailable']), walkthrough_fact(live),
       squash_fact(live), wip_fact(live)].compact
    end

    # One label names the one decision the PR waits on, so a missing label hides the PR from its searches.
    def label_fact(checks)
      @labels = Attention.new(@github).current
      return woken_fact if @woken_by
      return owe('no awaiting label', 'Set the attention label for what the PR waits on.') if @labels.empty?
      return owe(@labels.join('+'), "Keep exactly one attention label; found #{list}.") if @labels.length > 1

      if merge_requested? && !passing?(checks)
        @owed << 'awaiting-merge-approval is set while required checks are not all passing.'
      end
      @labels.first
    end

    # A wake source replaces the label: the agent acts next, so no person should see the PR in a queue.
    def woken_fact
      return "woken by #{@woken_by}" if @labels.empty?

      owe(@labels.join('+'), "Remove #{list}; #{@woken_by} wakes the agent, not a person.")
    end

    def checks_fact(checks, unavailable)
      return "required checks unavailable: #{unavailable}" if checks.nil?
      return 'no required checks' if checks.empty?

      counts = checks.map { |check| check['bucket'] }.tally.map { |bucket, count| "#{count} #{bucket}" }
      "required checks #{counts.join(', ')}"
    end

    # Judges each check with the merge gate's own test. An empty set passes, as Ask allows.
    def passing?(checks) = checks.is_a?(Array) && checks.all? { |check| passing_check?(check) }

    def walkthrough_fact(live)
      revision = Walkthrough.new(@github).revision
      unless revision
        return owe('no walkthrough', 'Publish a walkthrough before asking for merge.') if merge_requested?

        return note('no walkthrough', 'No walkthrough yet; one is required before merge.')
      end
      return "walkthrough #{revision[0, SHORT]}" if revision == live

      owe("walkthrough #{revision[0, SHORT]}", "The walkthrough explains #{revision}; publish one for #{live}.")
    end

    # Checked here because this helper's current code runs even for a session that loaded an older Finish.
    def squash_fact(live)
      return unless merge_requested?

      head = SquashNote.new(@github).head
      message = "Post the squash commit message for #{live} with `squash-message` before the merge click."
      return owe('no squash message', message) unless head
      return "squash message #{head[0, SHORT]}" if head == live

      owe("squash message #{head[0, SHORT]}", "The squash commit message names #{head}; post one for #{live}.")
    end

    def wip_fact(live)
      pull = @github.api("repos/#{@github.repository}/pulls/#{@github.number}")
      recheck_head(pull.dig('head', 'sha'), live)
      revision = WipNote.revision(pull['body'])
      return owe('no WIP', 'WIP Details is missing; publish it before stopping.') unless revision
      return "WIP #{live[0, SHORT]}" if WipNote.head(revision) == live

      owe('WIP stale', "WIP Details names #{revision}, not #{live}; refresh it.")
    end

    # The final read also returns the head, so a push during the earlier reads cannot pass as current.
    def recheck_head(moved, live)
      @owed << "PR head moved to #{moved} while handoff read it; run it again." if moved && moved != live
    end

    def list = @labels.join(', ')

    def merge_requested? = @labels.any? { |label| label.casecmp?('awaiting-merge-approval') }

    def owe(fact, item)
      @owed << item
      fact
    end

    def note(fact, item)
      @notes << item
      fact
    end
  end
end
