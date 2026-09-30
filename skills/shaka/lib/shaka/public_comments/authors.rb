# frozen_string_literal: true

require_relative '../error'
require_relative 'teams'
require_relative 'writers'

module Shaka
  module PublicComments
    # Screens public comment prose using GitHub's repository permission evidence.
    class Authors
      TRUSTED_PERMISSIONS = %w[write maintain admin].freeze
      KINDS = { 'issue_comments' => 'issue_comment', 'review_summaries' => 'review_summary',
                'inline_comments' => 'inline_comment' }.freeze

      def initialize(github, public_repo:, trust_config: nil)
        @github = github
        @public_repo = public_repo
        @trust_config = trust_config || { users: Set.new, bots: Set.new, metadata_bots: Set.new, teams: [] }
      end

      def screen(items, thread_index: {})
        items.fetch('inline_comments', []).each { |item| thread_metadata(item, thread_index) }
        context = screen_context(items, thread_index)
        kept = items.to_h do |key, rows|
          [key, filter(rows, KINDS.fetch(key), context)]
        end
        { 'excluded_interactions' => context[:excluded] }.merge(kept)
      end

      private

      def author(item) = item['user'].is_a?(Hash) ? item['user']['login'] : nil

      def human?(item) = item['user'].is_a?(Hash) && item['user']['type'] == 'User'

      def screen_context(items, thread_index)
        permissions, team_result = @public_repo ? author_evidence(human_logins(items)) : empty_author_evidence
        { permissions: permissions, team_members: team_result[:trusted],
          team_unavailable: team_result[:unavailable], excluded: [], thread_index: thread_index }
      end

      def empty_author_evidence = [{}, { trusted: Set.new, unavailable: Set.new }]

      def human_logins(items)
        items.values.flatten.filter_map do |item|
          login = author(item)
          login.downcase if human?(item) && login.is_a?(String)
        end.uniq
      end

      def author_evidence(logins)
        unknown = logins.uniq.reject { |login| configured_user?(login) }
        permissions = Writers.new(@github).permissions(unknown)
        nonwriters = unknown.reject { |login| TRUSTED_PERMISSIONS.include?(permissions[login]) }
        [permissions, Teams.new(@github).trusted(nonwriters, @trust_config[:teams])]
      end

      def configured_user?(login)
        login.is_a?(String) && @trust_config[:users].include?(login.downcase)
      end

      def permission_level(login, permissions)
        permissions[login.downcase] if login.is_a?(String)
      end

      def bot_in?(item, login, key)
        user = item['user']
        user.is_a?(Hash) && user['type'] == 'Bot' && login.is_a?(String) &&
          login.downcase.end_with?('[bot]') && @trust_config[key].include?(login.downcase.delete_suffix('[bot]'))
      end

      def trust_evidence(item, login, permissions, team_members)
        return 'private' unless @public_repo
        return 'configured_bot' if bot_in?(item, login, :bots)
        return unless human?(item)

        human_evidence(login, permissions, team_members)
      end

      def human_evidence(login, permissions, team_members)
        return 'configured_user' if configured_user?(login)
        return 'writer' if TRUSTED_PERMISSIONS.include?(permission_level(login, permissions))

        'team' if login.is_a?(String) && team_members.include?(login.downcase)
      end

      def filter(items, kind, context) = items.filter_map { |item| screen_item(item, kind, context) }

      def screen_item(item, kind, context)
        login = author(item)
        thread = thread_metadata(item, context[:thread_index]) if kind == 'inline_comment'
        evidence = trust_evidence(item, login, context[:permissions], context[:team_members])
        return kept_record(item, kind, login, thread).tap { |row| row['trust'] = evidence if @public_repo } if evidence

        context[:excluded] << excluded_record(item, kind, login, thread, context)
        item.delete('body')
        nil
      end

      def thread_metadata(item, index)
        meta = index[item['id']] || index[item['in_reply_to_id']]
        raise Error, 'Inline comment has no review-thread metadata.' unless meta

        meta
      end

      def kept_record(item, kind, login, thread)
        row = { 'id' => item['id'], 'author' => login, 'body' => item['body'], 'url' => item['html_url'] }
        row['state'] = item['state'] if kind == 'review_summary'
        row['commit_id'] = item['commit_id'] if kind == 'review_summary'
        row.merge!(inline_location(item)).merge!(thread) if kind == 'inline_comment'
        row
      end

      def inline_location(item)
        { 'path' => item['path'], 'line' => item['line'], 'original_line' => item['original_line'],
          'commit_id' => item['commit_id'], 'in_reply_to_id' => item['in_reply_to_id'] }
      end

      def excluded_record(item, kind, login, thread, context)
        evidence = permission_level(login, context[:permissions])
        unavailable = evidence == 'unavailable' ||
                      context[:team_unavailable].include?(login.to_s.downcase)
        row = { 'kind' => kind, 'id' => item['id'], 'author' => login,
                'url' => item['html_url'], 'body_withheld' => !item['body'].to_s.empty?,
                'verification_unavailable' => unavailable, 'prefiltered' => evidence == 'prefiltered',
                'trust' => bot_in?(item, login, :metadata_bots) ? 'metadata_only' : 'untrusted' }
        add_review_metadata(row, item, kind)
        row.merge!(thread) if kind == 'inline_comment'
        row
      end

      def add_review_metadata(row, item, kind)
        row.merge!('state' => item['state'], 'commit_id' => item['commit_id']) if kind == 'review_summary'
      end
    end
  end
end
