# frozen_string_literal: true

require_relative '../error'
require_relative 'authors'
require_relative 'trust_config'

module Shaka
  module PublicComments
    # Stops an inline reply when a public thread includes an author comments would exclude.
    # The refusal posts nothing, including no note that the author is approved or excluded.
    class ReplyGuard
      VISIBILITIES = %w[public private internal].freeze

      def initialize(github, trust_config:, machine_path:)
        @github = github
        @trust_config = trust_config
        @machine_path = machine_path
      end

      def check(listed, target, account)
        return unless target
        return unless public?

        participants = participants_for(listed, target)
        require_root(participants, target)
        refuse(excluded(participants, target, account))
      end

      private

      def participants_for(listed, target)
        listed.select { |item| participant?(item, target) }
      end

      def participant?(item, target)
        item.is_a?(Hash) && (item['id'] == target || item['in_reply_to_id'] == target)
      end

      def require_root(participants, target)
        root = participants.find { |item| item['id'] == target }
        raise Error, 'Inline thread root is not in the comment list. No comment was posted.' unless root
        return if root['in_reply_to_id'].nil?

        raise Error, 'Inline reply target must be the thread root. No comment was posted.'
      end

      def public?
        visibility = @github.api("repos/#{@github.repository}")['visibility']
        raise Error, 'Repository visibility is unavailable.' unless VISIBILITIES.include?(visibility)

        visibility == 'public'
      end

      def excluded(participants, target, account)
        others = participants.reject { |item| own_comment?(item, account) }
        return [] if others.empty?

        Authors.new(@github, public_repo: true, trust_config: config).screen(
          { 'inline_comments' => others }, thread_index: index(others, target)
        ).fetch('excluded_interactions')
      end

      def own_comment?(item, account)
        user = item['user']
        user.is_a?(Hash) && user['login'] == account
      end

      def config
        return @trust_config if @trust_config

        loader = TrustConfig.new(@github, machine_path: @machine_path)
        loader.load(base_oid: loader.default_base_oid)
      end

      def index(participants, target)
        meta = { 'thread_id' => "thread-#{target}", 'is_resolved' => false }
        participants.to_h { |item| [item['id'], meta] }
      end

      def refuse(rows)
        return if rows.empty?

        names = rows.filter_map { |row| row['author'] }.uniq
        detail = names.empty? ? 'an excluded author' : names.join(', ')
        raise Error, "Refusing to reply in a public thread that includes an excluded author (#{detail}). " \
                     'No comment was posted.'
      end
    end
  end
end
