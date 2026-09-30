# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/handoff'
require 'shaka/publication/publication'
require 'shaka/publication/publishing'

# Answers the reads handoff makes, so each test states only the PR state it cares about.
class HandoffFakeGitHub
  LABELS = 'repos/owner/repo/issues/42/labels'
  REVIEWS = 'repos/owner/repo/pulls/42/reviews'
  COMMENTS = 'repos/owner/repo/issues/42/comments'

  attr_reader :repository, :number

  def initialize(pull)
    @repository = 'owner/repo'
    @number = 42
    @pull = pull
  end

  def snapshot = { 'state' => @pull[:state], 'headRefOid' => @pull[:head], 'number' => 42 }
  def required_checks = @pull[:checks]
  def configured_required_checks = []

  def api(path, **)
    return { 'login' => 'shaka-agent' } if path == 'user'
    raise "unexpected read #{path}" unless path == 'repos/owner/repo/pulls/42'

    { 'body' => @pull[:body], 'head' => { 'sha' => @pull.fetch(:final_head, @pull[:head]) } }
  end

  def api_list(path)
    return @pull[:labels].map { |name| { 'name' => name } } if path.start_with?(HandoffFakeGitHub::LABELS)
    return @pull[:reviews] if path.start_with?(HandoffFakeGitHub::REVIEWS)
    return @pull[:comments] if path.start_with?(HandoffFakeGitHub::COMMENTS)

    raise "unexpected list #{path}"
  end
end

# Renders the PR text handoff reads, so parsing is tested against what the helper publishes.
module HandoffFixtures
  HEAD = 'a' * 40
  OLD = 'c' * 40
  WIP = { 'owner' => 'm5 · Claude Code · k7q2', 'task' => 'shaka #256 handoff', 'thread' => 'UNKNOWN',
          'last_observed_activity' => '2026-09-25 13:31 HST', 'revision' => "feature @ #{HEAD}",
          'workspace' => 'UNKNOWN', 'unfinished_work' => 'none', 'stopped_because' => 'paused',
          'merge_authority' => 'ask', 'state' => 'awaiting hosted checks', 'next_action' => 'rerun handoff' }.freeze

  IDENTITY = { 'agent' => 'Claude Code', 'provider' => 'Anthropic', 'model' => 'claude-opus-5-5',
               'effort' => 'medium' }.freeze
  PROVENANCE = { 'task_source' => 'issue', 'initial_prompt' => 'EXCLUDED',
                 'requested_model' => 'UNKNOWN', 'requested_effort' => 'UNKNOWN',
                 'recommended_model' => 'UNKNOWN', 'recommended_effort' => 'UNKNOWN',
                 'active_model' => 'UNKNOWN', 'active_effort' => 'UNKNOWN' }.freeze
  TABLE = { 'columns' => %w[Check Result], 'rows' => [%w[validate pass]] }.freeze
  USAGE_COLUMN = {
    'label' => 'anthropic', 'provider' => 'anthropic', 'model' => 'claude-opus-5-5', 'routed' => 'UNKNOWN',
    'effort' => 'medium', 'credits' => 'UNKNOWN', 'usd' => 'UNKNOWN', 'input' => '1',
    'cached_input' => '0', 'output' => '0', 'reasoning_output' => 'UNKNOWN', 'cache_writes' => 'UNKNOWN'
  }.freeze
  USAGE = { 'note' => 'Native usage is PARTIAL.',
            'records' => [USAGE_RECORD.merge('columns' => [USAGE_COLUMN])] }.freeze

  def self.rendered(wip = WIP)
    Shaka::Publication.description(
      'identity' => IDENTITY, 'summary' => 'A summary.', 'table' => TABLE, 'deployment' => 'none',
      'provenance' => PROVENANCE, 'usage' => USAGE, 'details' => [], 'wip' => wip
    )
  end

  # The body as `description` stores it: the rendered text inside the helper's markers.
  def self.walkthrough(head, author: 'shaka-agent', commit: head)
    body = Shaka::Publication.walkthrough('identity' => IDENTITY, 'summary' => 'What changed.', 'head' => head)
    { 'id' => 7, 'state' => 'COMMENTED', 'body' => body, 'submitted_at' => '2026-09-25T00:00:00Z',
      'user' => { 'login' => author }, 'commit_id' => commit }
  end

  STATES = { 'pass' => 'SUCCESS', 'pending' => 'PENDING', 'skipping' => 'SKIPPED' }.freeze

  def self.check(bucket) = { 'name' => 'validate', 'state' => STATES.fetch(bucket), 'bucket' => bucket }

  def self.description(wip = WIP) = "#{Shaka::Publishing::OPEN_MARK}\n#{rendered(wip)}#{Shaka::Publishing::CLOSE_MARK}"
end

# Runs handoff against a fake PR whose defaults owe nothing, so each test changes one fact.
module HandoffHarness
  include HandoffFixtures

  def walkthrough(...) = HandoffFixtures.walkthrough(...)
  def check(bucket) = HandoffFixtures.check(bucket)

  def description(wip = WIP) = HandoffFixtures.description(wip)

  def handoff(expected: HEAD, woken_by: nil, **pull)
    defaults = { state: 'OPEN', head: HEAD, labels: ['awaiting-resume'], body: description,
                 reviews: [walkthrough(HEAD)], checks: [check('pass')], comments: [] }
    Shaka::Handoff.new(HandoffFakeGitHub.new(defaults.merge(pull))).call(head: expected, woken_by:)
  end
end
