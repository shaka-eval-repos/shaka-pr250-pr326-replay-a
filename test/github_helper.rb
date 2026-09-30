# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/github'

module GitHubHelper
  HEAD = 'a' * 40
  BASE = 'b' * 40
  STATUS = Struct.new(:exitstatus)
  CHANGED_FILE = 'skills/shaka/config/workflow.yml'
  PINNED_LINK = "https://github.com/owner/repo/blob/#{HEAD}/#{CHANGED_FILE}#L154-L156".freeze
  WALKTHROUGH = "See #{PINNED_LINK}. Gates: validate, claude-review.".freeze
  COMPLETED_GATES = [
    { 'name' => 'validate', 'state' => 'SUCCESS', 'bucket' => 'pass' },
    { 'name' => 'claude-review', 'state' => 'SUCCESS', 'bucket' => 'pass' }
  ].freeze

  def client(*responses)
    @calls = []
    runner = lambda do |argv, stdin_data:|
      @calls << [argv, stdin_data]
      responses.shift || raise('Unexpected GitHub request')
    end
    Shaka::GitHub.new('owner/repo', 42, runner: runner)
  end

  def response(value, status: 0, http_status: nil)
    stderr = http_status ? "gh: request failed (HTTP #{http_status})" : 'private stderr must not be disclosed'
    [JSON.generate(value), stderr, STATUS.new(status)]
  end

  def snapshot_response(head: HEAD, state: 'OPEN')
    response({ 'data' => { 'repository' => { 'pullRequest' => { 'headRefOid' => head, 'state' => state } } } })
  end

  def review_response(body: WALKTHROUGH, **changes)
    response({ 'id' => 123, 'state' => 'COMMENTED', 'commit_id' => HEAD, 'body' => body,
               'submitted_at' => '2026-09-24T08:00:00Z' }.merge(changes))
  end

  def files_response(names = [CHANGED_FILE])
    response(names.map { |name| { 'filename' => name } })
  end

  def gate_responses
    required = [{ 'name' => 'validate', 'state' => 'SUCCESS', 'bucket' => 'pass' }]
    [response(required), response(COMPLETED_GATES)]
  end

  def html_response(html = '<p>A walkthrough.</p>')
    [html, 'private stderr must not be disclosed', STATUS.new(0)]
  end

  def publish_responses(*extra)
    [snapshot_response, files_response, *gate_responses, html_response, review_response, review_response, *extra]
  end

  def no_configured_requirements
    base = { 'baseRefName' => 'main', 'baseRef' => { 'refUpdateRule' => nil } }
    [response({ 'data' => { 'repository' => { 'pullRequest' => base } } }), response([])]
  end

  def pending_review_gate_responses
    passed = { 'name' => 'validate', 'state' => 'SUCCESS', 'bucket' => 'pass' }
    pending = { 'name' => 'claude-review', 'state' => 'PENDING', 'bucket' => 'pending' }
    [response([passed]), response([passed, pending])]
  end
end
