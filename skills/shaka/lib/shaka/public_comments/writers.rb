# frozen_string_literal: true

require_relative '../error'
require_relative 'github_login'

module Shaka
  module PublicComments
    # Narrows high-volume public authors in batches before final REST permission checks.
    class Writers
      LOGIN = GitHubLogin::PATTERN
      DIRECT_LIMIT = 8
      BATCH_SIZE = 50
      MAX_AUTHORS = 500
      MAX_CONFIRMATIONS = 100
      GRAPH_PERMISSIONS = %w[READ TRIAGE WRITE MAINTAIN ADMIN].freeze
      REST_PERMISSIONS = %w[none read write admin].freeze
      WRITER_ROLES = %w[WRITE MAINTAIN ADMIN].freeze

      def initialize(github)
        @github = github
      end

      def permissions(logins)
        valid = GitHubLogin.valid(logins)
        return {} if valid.empty?
        raise Error, 'Too many public comment authors for a bounded trust read.' if valid.length > MAX_AUTHORS

        candidates = valid.length <= DIRECT_LIMIT ? valid : batched_candidates(valid)
        if candidates.length > MAX_CONFIRMATIONS
          raise Error, "Repository writer evidence exceeds #{MAX_CONFIRMATIONS} confirmations."
        end

        prefix = "repos/#{@github.repository}"
        checked = candidates.to_h { |login| [login, permission_for(prefix, login)] }
        mark_prefiltered(valid, candidates, checked)
      end

      private

      def mark_prefiltered(valid, candidates, checked)
        return checked if valid.length <= DIRECT_LIMIT

        (valid - candidates).to_h { |login| [login, 'prefiltered'] }.merge(checked)
      end

      def batched_candidates(logins)
        logins.each_slice(BATCH_SIZE).flat_map { |slice| graph_candidates(slice) }
      rescue Error
        raise Error, 'Repository writer evidence is unavailable; GitHub collaborator access is required.'
      end

      def graph_candidates(logins)
        query, variables = query_for(logins)
        response = @github.graphql(query, variables)
        repository = response['repository']
        raise Error, 'Malformed repository writer response.' unless repository.is_a?(Hash)

        logins.each_with_index.filter_map do |login, index|
          role = collaborator_role(repository["u#{index}"], login)
          login if WRITER_ROLES.include?(role)
        end
      end

      def query_for(logins)
        owner, name = @github.repository.split('/')
        declarations = logins.each_index.map { |index| "$login#{index}: String!" }.join(', ')
        fields = logins.each_index.map do |index|
          "u#{index}: collaborators(first: 1, login: $login#{index}) { edges { node { login } permission } }"
        end.join(' ')
        query = "query($owner: String!, $name: String!, #{declarations}) { " \
                "repository(owner: $owner, name: $name) { #{fields} } }"
        variables = { owner: owner, name: name }
        logins.each_with_index { |login, index| variables["login#{index}"] = login }
        [query, variables]
      end

      def collaborator_role(connection, login)
        edges = connection['edges'] if connection.is_a?(Hash)
        raise Error, 'Malformed repository writer response.' unless edges.is_a?(Array) && edges.length <= 1
        return if edges.empty?

        edge = edges.first
        raise Error, 'Malformed repository writer response.' unless valid_edge?(edge, login)

        permission = edge['permission']
        raise Error, 'Malformed repository writer response.' unless GRAPH_PERMISSIONS.include?(permission)

        permission
      end

      def valid_edge?(edge, login)
        return false unless edge.is_a?(Hash)

        user = edge['node']
        user.is_a?(Hash) && user['login'].is_a?(String) && user['login'].casecmp?(login) &&
          edge['permission'].is_a?(String)
      end

      def permission_for(prefix, login)
        result = @github.api("#{prefix}/collaborators/#{login}/permission")
        user = result['user']
        return 'unavailable' unless user.is_a?(Hash) && user['login'].is_a?(String) && user['login'].casecmp?(login)

        permission = result['permission']
        REST_PERMISSIONS.include?(permission) ? permission : 'unavailable'
      rescue Error
        'unavailable'
      end
    end
  end
end
