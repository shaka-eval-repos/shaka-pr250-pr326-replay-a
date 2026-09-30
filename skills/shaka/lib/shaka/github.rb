# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'error'
require_relative 'publication/publishing'
require_relative 'prose_limits'
require_relative 'review_thread'
require_relative 'walkthrough/evidence'
require_relative 'walkthrough/history'
require_relative 'github/check_list'
require_relative 'github/required_check_rules'
require_relative 'github/review_evidence_reads'
require_relative 'github/squash_comment'
require_relative 'github/prose_description'

module Shaka
  # The native pull-request evidence a publication decision depends on.
  SNAPSHOT_QUERY = <<~GRAPHQL
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          id number url state isDraft headRefOid baseRefName merged mergeCommit { oid }
          mergeStateStatus reviewDecision viewerCanMergeAsAdmin
          changedFiles additions deletions commits { totalCount }
          isInMergeQueue isMergeQueueEnabled autoMergeRequest { enabledAt }
          mergeQueueEntry {
            id position state estimatedTimeToMerge
            headCommit { oid }
            baseCommit { oid }
          }
          headRepository { nameWithOwner } baseRepository { nameWithOwner }
        }
      }
    }
  GRAPHQL
  MERGE_QUEUE_FEATURE = 'merge_queue'

  # Adds feature-aware GraphQL requests while preserving keyword-variable callers.
  module GraphqlTransport
    def graphql(query, variables = {}, feature: nil, **keyword_variables)
      variables = keyword_variables unless keyword_variables.empty?
      headers = feature ? ["GraphQL-Features: #{feature}"] : []
      response = api('graphql', method: 'POST', fields: { query: query, variables: variables }, headers: headers)
      raise Error, 'GraphQL failed or returned missing data.' if response['errors'] || !response['data'].is_a?(Hash)

      response['data']
    end
  end

  # Reads native PR evidence and publishes reviews bound to its current commit.
  class GitHub
    include Publishing
    include GraphqlTransport
    include CheckList
    include RequiredCheckRules
    include ReviewEvidenceReads
    include SquashComment
    include ProseDescription

    attr_reader :repository, :number

    def initialize(repository, number, runner: nil)
      unless repository.is_a?(String) && repository.ascii_only? &&
             repository.match?(%r{\A[\w-]+/(?!\.{1,2}\z)[\w.-]+\z})
        raise Error, 'Expected a GitHub repository in OWNER/REPO form.'
      end

      @repository = repository
      @number = positive_integer(number)
      @runner = runner || ->(argv, stdin_data:) { Open3.capture3(*argv, stdin_data: stdin_data) }
    end

    def snapshot
      owner, name = @repository.split('/')
      repository = graphql(SNAPSHOT_QUERY, { owner: owner, name: name, number: @number },
                           feature: MERGE_QUEUE_FEATURE)['repository']
      result = repository['pullRequest'] if repository.is_a?(Hash)
      raise Error, 'GitHub did not return the requested pull request.' unless result.is_a?(Hash)

      result
    end

    def review(id)
      api("#{reviews_path}/#{positive_integer(id)}")
    end

    def resolve_thread(thread_id)
      ReviewThread.resolve(self, thread_id)
    end

    def walkthrough(head:, body:, seam_required_checks: nil, prose: ProseLimits.new)
      body = publishable(body)
      changed_lines = ProseLimits.changed_lines(verify_head(head))
      WalkthroughEvidence.new(self, seam_required_checks:).verify(head, body)
      published = record_walkthrough(head, body) { |html| prose.verify!(html, kind: :walkthrough, changed_lines:) }
      published.merge('earlier_walkthroughs' => WalkthroughHistory.new(self).collapse(published))
    end

    def api(path, method: 'GET', fields: {}, expected: Hash, headers: [])
      argv = ['gh', 'api', path]
      headers.each { |header| argv.push('-H', header) }
      argv.push('--method', method, '--input', '-')
      result = execute(argv, input: JSON.generate(fields))
      raise Error, 'GitHub API response has an unexpected type.' unless result.is_a?(expected)

      result
    end

    def api_list(path) = api(path, expected: Array)

    private

    def positive_integer(value)
      unless value.to_s.ascii_only? && value.to_s.match?(/\A[1-9]\d*\z/)
        raise Error, 'Expected a positive integer identifier.'
      end

      value.to_i
    end

    def reviews_path = "repos/#{@repository}/pulls/#{@number}/reviews"

    def record_walkthrough(head, body)
      yield verify_rendering(body)
      created = api(reviews_path, method: 'POST', fields: { event: 'COMMENT', commit_id: head, body: body })
      published = review(created['id'])
      verify_review(published, created['id'], head, body)
      verify_head(head, review_id: created['id'])
      published
    end

    def verify_head(head, review_id: nil)
      raise Error, 'Expected a full commit SHA.' unless head.is_a?(String) && head.match?(/\A[0-9a-f]{40}\z/)

      pr = snapshot
      return pr if pr['state'] == 'OPEN' && pr['headRefOid'] == head

      detail = review_id ? " Review #{review_id} was created; inspect the PR before retrying." : ''
      raise Error, "Pull request is not open at the expected head.#{detail}"
    end

    def verify_review(review, id, head, body)
      return if review.values_at('id', 'state', 'commit_id', 'body') == [id, 'COMMENTED', head, body]

      raise Error, 'Published walkthrough review did not match its commit, body, or COMMENT state.'
    end

    def execute(argv, input: '', accepted: [0]) = parse_json(capture(argv, input: input, accepted: accepted))

    def capture(argv, input: '', accepted: [0])
      stdout, stderr, status = @runner.call(argv, stdin_data: input)
      detail = argv[1] == 'api' ? argv.drop(2).find { |arg| !arg.start_with?('-') } : argv[2]
      unless accepted.include?(status.exitstatus)
        raise Error.from_gh("gh #{argv[1]} #{detail} failed (exit #{status.exitstatus}).", stderr)
      end

      utf8(stdout)
    rescue Errno::ENOENT
      raise Error, 'GitHub CLI is unavailable; install gh and authenticate.'
    end

    def parse_json(output)
      JSON.parse(utf8(output))
    rescue JSON::ParserError
      raise Error, 'GitHub returned invalid JSON.'
    end

    def utf8(value)
      raise Error, 'Expected UTF-8 text.' unless value.is_a?(String)

      text = value.dup.force_encoding(Encoding::UTF_8)
      raise Error, 'Invalid UTF-8 text.' unless text.valid_encoding?

      text
    end
  end
end
