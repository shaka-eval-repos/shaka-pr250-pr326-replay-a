# frozen_string_literal: true

module Shaka
  class Claim
    # Compiles a repository branch-name template, or the tracker's branch name, into a matcher for remote heads.
    class Names
      DEFAULT = '{login}-{host}/{issue}-{description}'
      WILDCARDS = { 'login' => '[^/]+', 'host' => '[^/]+', 'description' => '.+' }.freeze

      def initialize(query:, template:, exact: nil)
        @query = query
        @template = template
        @exact = exact
      end

      def reported = @exact || @template || DEFAULT

      def cover?(name)
        name == @exact || name.match?(issue_token_pattern) || template_match?(name)
      end

      private

      # Trackers such as Linear lowercase the key in the branch names they generate.
      def issue_token_pattern = %r{(?:^|/)#{Regexp.escape(@query)}-}i

      def template_match?(name)
        return false if @template.nil? || @template.strip.empty?

        name.match?(template_pattern)
      end

      def template_pattern
        @template_pattern ||= begin
          pieces = @template.split(/\{(login|host|issue|description)\}/)
          regex = pieces.each_with_index.map { |piece, index| index.even? ? Regexp.escape(piece) : token_regex(piece) }
          Regexp.new("\\A#{regex.join}\\z")
        end
      end

      def token_regex(token)
        token == 'issue' ? "(?i:#{Regexp.escape(@query)})" : WILDCARDS.fetch(token)
      end
    end
  end
end
