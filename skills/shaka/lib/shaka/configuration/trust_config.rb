# frozen_string_literal: true

require_relative '../error'
require_relative 'trust_settings'
require_relative 'paths'

module Shaka
  module PublicComments
    # Reads the predecessor trust-config keys without adopting its workflow policy engine.
    class TrustConfig
      MACHINE_PATH = Configuration::Paths::MACHINE_ALLOWLIST
      REPO_PATH = Configuration::Paths::REPOSITORY_ALLOWLIST
      NEW_REPO_PATH = Configuration::Paths::NEW_REPOSITORY_ALLOWLIST
      BLOB_QUERY = <<~GRAPHQL
        query($owner: String!, $name: String!, $expression: String!, $newExpression: String!) {
          repository(owner: $owner, name: $name) {
            object(expression: $expression) {
              __typename
              ... on Blob { text isBinary isTruncated byteSize }
            }
            newObject: object(expression: $newExpression) {
              __typename
              ... on Blob { text isBinary isTruncated byteSize }
            }
          }
        }
      GRAPHQL
      DEFAULT_QUERY = <<~GRAPHQL
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            defaultBranchRef { target { oid } }
          }
        }
      GRAPHQL

      def initialize(github, machine_path: MACHINE_PATH)
        @github = github
        @machine_path = File.expand_path(machine_path)
      end

      def default_base_oid
        owner, name = @github.repository.split('/')
        result = @github.graphql(DEFAULT_QUERY, owner: owner, name: name)
        oid = result.dig('repository', 'defaultBranchRef', 'target', 'oid')
        valid_oid(oid)
      end

      def load(base_oid:)
        valid_oid(base_oid)
        merged_config([machine_config, repository_config(base_oid)].compact)
      end

      def verify_machine_source(sources)
        expected = sources.find { |source| source['scope'] == 'machine' }
        current = machine_config&.fetch(:provenance)
        raise Error, 'Machine trust config changed during comment read.' unless current == expected
      end

      def verify_repository_source(sources, base_oid)
        expected = sources.find { |source| source['scope'] == 'repository' }
        current = repository_config(base_oid)&.fetch(:provenance)
        raise Error, 'Repository trust config changed during comment read.' unless current == expected
      end

      private

      def valid_oid(value)
        raise Error, 'Trusted default-branch commit is unavailable.' unless value.is_a?(String) &&
                                                                            value.match?(/\A[0-9a-f]{40}\z/)

        value
      end

      def machine_config
        return unless File.exist?(@machine_path)
        raise Error, 'Machine trust config is not a file.' unless File.file?(@machine_path)

        settings.parse(File.binread(@machine_path), scope: 'machine')
      rescue SystemCallError
        raise Error, 'Machine trust config is unreadable.'
      end

      def repository_config(base_oid)
        object, path = repository_blob(base_oid)
        return if object.nil?
        raise Error, "Trusted-base #{path} is not readable text." unless valid_blob?(object)

        parsed = settings.parse(object['text'], scope: 'repository')
        parsed.fetch(:provenance)['path'] = path
        parsed
      end

      def repository_blob(base_oid)
        owner, name = @github.repository.split('/')
        result = @github.graphql(BLOB_QUERY, owner: owner, name: name,
                                             expression: "#{base_oid}:#{REPO_PATH}",
                                             newExpression: "#{base_oid}:#{NEW_REPO_PATH}")
        repository = result['repository']
        raise Error, 'Trusted-base repository trust config is unavailable.' unless repository.is_a?(Hash)

        legacy = repository['object']
        modern = repository['newObject']
        raise Error, "Both #{REPO_PATH} and #{NEW_REPO_PATH} exist" if legacy && modern

        [legacy || modern, modern ? NEW_REPO_PATH : REPO_PATH]
      end

      def valid_blob?(object)
        object['__typename'] == 'Blob' && object['isBinary'] == false && object['isTruncated'] == false &&
          object['byteSize'].is_a?(Integer) && object['byteSize'] <= TrustSettings::MAX_BYTES &&
          object['text'].is_a?(String)
      end

      def settings
        @settings ||= TrustSettings.new(@github.repository)
      end

      def merged_config(sources)
        bots = combined(sources, :bots).to_set
        metadata_bots = combined(sources, :metadata_bots).to_set
        raise Error, 'A trust bot is also metadata-only.' if bots.intersect?(metadata_bots)

        { users: combined(sources, :users).to_set, bots: bots, metadata_bots: metadata_bots,
          teams: combined(sources, :teams).uniq,
          sources: sources.map { |source| source.fetch(:provenance) } }
      end

      def combined(sources, key)
        sources.flat_map { |source| source.fetch(key) }
      end
    end
  end
end
