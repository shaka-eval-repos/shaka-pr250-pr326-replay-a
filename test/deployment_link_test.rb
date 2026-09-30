# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/publication/deployment_link'

# Resolves `deployment: auto` from the GitHub Deployments API, the record behind
# the "View deployment" button, instead of parsing provider comments.
class DeploymentLinkTest < Minitest::Test
  HEAD = 'a' * 40

  # Answers the deployment reads for one pull request head.
  class RecordedGitHub
    attr_reader :repository, :reads

    def initialize(deployments, statuses)
      @repository = 'owner/repo'
      @deployments = deployments
      @statuses = statuses
      @reads = []
    end

    def snapshot = { 'headRefOid' => HEAD }

    def api_list(path)
      @reads << path
      return @deployments if path == "repos/owner/repo/deployments?sha=#{HEAD}&per_page=100"

      id = path[%r{\Arepos/owner/repo/deployments/(\d+)/statuses\?per_page=1\z}, 1]
      raise Shaka::Error, "Unexpected read: #{path}" unless id

      Array(@statuses.fetch(id.to_i))
    end
  end

  def status(state, url = nil) = { 'state' => state, 'environment_url' => url }

  def resolve(deployments, statuses, deployment: 'auto')
    Shaka::DeploymentLink.resolve({ 'deployment' => deployment }, RecordedGitHub.new(deployments, statuses))
  end

  def test_auto_uses_the_newest_successful_deployment_url_for_the_head
    deployments = [{ 'id' => 2, 'created_at' => '2026-09-24T02:00:00Z' },
                   { 'id' => 1, 'created_at' => '2026-09-24T01:00:00Z' }]
    statuses = { 2 => [status('success', 'https://new.example')], 1 => [status('success', 'https://old.example')] }

    assert_equal({ 'deployment' => 'https://new.example' }, resolve(deployments, statuses))
  end

  def test_auto_skips_failed_inactive_and_url_less_deployments
    deployments = [{ 'id' => 4, 'created_at' => '2026-09-24T04:00:00Z' },
                   { 'id' => 3, 'created_at' => '2026-09-24T03:00:00Z' },
                   { 'id' => 2, 'created_at' => '2026-09-24T02:00:00Z' },
                   { 'id' => 1, 'created_at' => '2026-09-24T01:00:00Z' }]
    statuses = { 4 => [status('failure')], 3 => [status('inactive', 'https://gone.example')],
                 2 => [status('success')], 1 => [status('success', 'https://live.example')] }

    assert_equal 'https://live.example', resolve(deployments, statuses)['deployment']
  end

  def test_auto_records_none_when_the_head_has_no_live_deployment
    assert_equal 'none', resolve([], {})['deployment']
    assert_equal 'none', resolve([{ 'id' => 1, 'created_at' => 'x' }], { 1 => [] })['deployment']
  end

  def test_a_full_page_without_a_live_deployment_is_not_reported_as_none
    deployments = Array.new(100) { |index| { 'id' => index + 1, 'created_at' => format('%03d', index) } }
    statuses = deployments.to_h { |deployment| [deployment['id'], [status('failure')]] }

    error = assert_raises(Shaka::Error) { resolve(deployments, statuses) }
    assert_includes error.message, 'deployment: auto'
  end

  def test_a_supplied_url_or_none_is_left_alone_without_reading_github
    github = RecordedGitHub.new([], {})
    %w[https://preview.example none].each do |value|
      assert_equal({ 'deployment' => value }, Shaka::DeploymentLink.resolve({ 'deployment' => value }, github))
    end
    assert_empty github.reads
  end
end
