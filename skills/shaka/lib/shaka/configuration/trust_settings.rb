# frozen_string_literal: true

require 'digest'
require 'yaml'
require_relative '../error'
require_relative '../public_comments/github_login'

module Shaka
  module PublicComments
    # Parses the compatible predecessor YAML fields as data, with strict pilot bounds.
    class TrustSettings
      LOGIN = GitHubLogin::PATTERN
      TEAM_SLUG = /\A[A-Za-z0-9](?:[A-Za-z0-9_-]{0,99})\z/
      MAX_BYTES = 65_536
      KEYS = %w[trusted_users trusted_bots trusted_metadata_bots trusted_teams].freeze

      def initialize(repository)
        @owner = repository.split('/').first.downcase
      end

      def parse(contents, scope:)
        text = utf8(contents)
        values = lists(YAML.safe_load(text, aliases: false) || {})
        build(values, scope: scope, text: text)
      rescue Psych::Exception
        raise Error, 'Trust config contains malformed or unsafe YAML.'
      end

      private

      def utf8(contents)
        text = contents.dup.force_encoding(Encoding::UTF_8)
        raise Error, 'Trust config must be bounded UTF-8 text.' if text.bytesize > MAX_BYTES || !text.valid_encoding?

        text
      end

      def lists(data)
        raise Error, 'Trust config must be a YAML mapping.' unless data.is_a?(Hash)

        extra = data.keys - KEYS
        raise Error, "Trust config has unsupported keys: #{extra.join(', ')}" unless extra.empty?

        KEYS.to_h do |key|
          rows = data.fetch(key, [])
          raise Error, "Trust config #{key} must be a list." unless rows.is_a?(Array)

          [key, rows]
        end
      end

      def build(values, scope:, text:)
        { users: logins(values['trusted_users']), bots: logins(values['trusted_bots']),
          metadata_bots: logins(values['trusted_metadata_bots']),
          teams: values['trusted_teams'].filter_map { |entry| team(entry, scope) },
          provenance: { 'scope' => scope, 'sha256' => Digest::SHA256.hexdigest(text) } }
      end

      def logins(values)
        values.map do |value|
          unless value.is_a?(String) && value.match?(LOGIN)
            raise Error,
                  'Trust config contains an invalid GitHub login.'
          end

          value.downcase
        end
      end

      def team(entry, scope)
        owner, slug = team_parts(entry, scope)
        if owner && !owner.casecmp?(@owner)
          raise Error, 'Repository team owner must match repository owner.' if scope == 'repository'

          return
        end
        [@owner, slug.downcase]
      end

      def team_parts(entry, scope)
        raise Error, 'Trust config contains an invalid team.' unless entry.is_a?(String)

        owner, slug = entry.include?('/') ? entry.split('/', 2) : [nil, entry]
        validate_team_parts(owner, slug, scope)
        [owner, slug]
      end

      def validate_team_parts(owner, slug, scope)
        raise Error, 'Machine teams need OWNER/slug.' if scope == 'machine' && owner.nil?
        raise Error, 'Trust config contains an invalid team.' unless slug.match?(TEAM_SLUG) &&
                                                                     (owner.nil? || owner.match?(LOGIN))
      end
    end
  end
end
