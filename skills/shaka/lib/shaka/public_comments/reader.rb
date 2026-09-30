# frozen_string_literal: true

require_relative '../error'
require_relative 'authors'
require_relative 'bounded_list'
require_relative 'threads'
require_relative 'trust_config'

module Shaka
  module PublicComments
    # Reads one issue or PR discussion at a stable visibility and PR head.
    class Reader
      MAX_COMMENT_PAGES = 10
      def initialize(github, trust_config: nil, machine_path: TrustConfig::MACHINE_PATH)
        @github = github
        @trust_config = trust_config
        @machine_path = machine_path
      end

      def call(issue_only: false, expected_head: nil)
        pull, visibility, config, base_oid = read_context(issue_only, expected_head)
        items = fetch_items(issue_only:)
        threads, index = issue_only ? [[], {}] : Threads.new(@github).call
        screened = screen(items, visibility, config, index)
        verify_context(pull && pull['headRefOid'], visibility, base_oid, config)
        verify_machine_config(config) if visibility == 'public' && !@trust_config
        packet(pull, visibility, config, threads, screened)
      end

      private

      def read_context(issue_only, expected_head)
        pull = issue_only ? issue_head(expected_head) : pr_snapshot(expected_head)
        visibility = repository_visibility
        config, base_oid = visibility == 'public' ? public_config : [nil, nil]
        [pull, visibility, config, base_oid]
      end

      def screen(items, visibility, config, index)
        Authors.new(@github, public_repo: visibility == 'public', trust_config: config)
               .screen(items, thread_index: index)
      end

      def packet(pull, visibility, config, threads, screened)
        { 'visibility' => visibility, 'head' => pull && pull['headRefOid'],
          'review_threads' => threads, 'trust_sources' => config ? config[:sources] : [] }.merge(screened)
      end

      def pr_snapshot(expected)
        raise Error, 'Expected a full PR head.' unless expected.is_a?(String) && expected.match?(/\A[0-9a-f]{40}\z/)

        pull = open_snapshot
        return pull if expected == pull['headRefOid']

        raise Error, 'Pull request head no longer matches the expected head.'
      end

      def issue_head(expected)
        raise Error, 'Issue comments have no expected PR head.' unless expected.nil?

        issue = @github.api("repos/#{@github.repository}/issues/#{@github.number}")
        raise Error, 'Expected a GitHub issue, not a pull request.' if issue.key?('pull_request')

        nil
      end

      def open_snapshot
        pull = @github.snapshot
        raise Error, 'PR must be open for a comment read.' unless pull['state'] == 'OPEN'

        pull
      end

      def public_config
        loader = TrustConfig.new(@github, machine_path: @machine_path)
        base_oid = loader.default_base_oid unless @trust_config

        [@trust_config || loader.load(base_oid: base_oid), base_oid]
      end

      def verify_context(head, visibility, base_oid, config)
        verify_pull_context(head) if head
        verify_default_config(base_oid, config[:sources]) if base_oid
        raise Error, 'Repository visibility changed during comment read.' unless repository_visibility == visibility
      end

      def verify_pull_context(head)
        pull = open_snapshot
        raise Error, 'PR head changed or closed during comment read.' unless pull['headRefOid'] == head
      end

      def verify_default_config(base_oid, sources)
        loader = TrustConfig.new(@github, machine_path: @machine_path)
        current = loader.default_base_oid
        loader.verify_repository_source(sources, current) unless current == base_oid
      end

      def verify_machine_config(config)
        TrustConfig.new(@github, machine_path: @machine_path).verify_machine_source(config[:sources])
      end

      def repository_visibility
        metadata = @github.api("repos/#{@github.repository}")
        visibility = metadata['visibility']
        raise Error, 'Repository visibility is unavailable.' unless %w[public private internal].include?(visibility)

        visibility
      end

      def fetch_items(issue_only:)
        prefix = "repos/#{@github.repository}"
        number = @github.number
        items = { 'issue_comments' => fetch_page("#{prefix}/issues/#{number}/comments") }
        return items if issue_only

        items['review_summaries'] = fetch_page("#{prefix}/pulls/#{number}/reviews")
        items['inline_comments'] = fetch_page("#{prefix}/pulls/#{number}/comments")
        items
      end

      def fetch_page(path)
        BoundedList.new(@github, max_pages: MAX_COMMENT_PAGES, label: 'GitHub comment list').call(path)
      end
    end
  end
end
