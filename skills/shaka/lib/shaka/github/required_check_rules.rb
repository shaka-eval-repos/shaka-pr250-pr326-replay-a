# frozen_string_literal: true

require 'uri'

module Shaka
  class GitHub
    # Reads the checks a PR's base branch is configured to require, including ones that have not
    # reported yet, which `gh pr checks --required` cannot see.
    module RequiredCheckRules
      BASE_RULE_QUERY = <<~GRAPHQL
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              baseRefName
              baseRef { refUpdateRule { requiredStatusCheckContexts } }
            }
          }
        }
      GRAPHQL
      # GitHub Free offers no rulesets on private repositories, so none can require a check there.
      PLAN_WITHOUT_RULESETS = /Upgrade to GitHub Pro or make this repository public/
      RULES_PAGE = 100

      # Classic protection comes from refUpdateRule, which non-admins can read; rulesets do not appear there.
      def configured_required_checks
        owner, name = @repository.split('/')
        pull = graphql(BASE_RULE_QUERY, { owner:, name:, number: @number }).dig('repository', 'pullRequest')
        branch = pull['baseRefName'] if pull.is_a?(Hash)
        raise Error, 'GitHub did not report the pull request base branch.' unless branch.is_a?(String)

        classic = pull.dig('baseRef', 'refUpdateRule', 'requiredStatusCheckContexts') || []
        (classic + ruleset_contexts(branch)).uniq
      end

      private

      def ruleset_contexts(branch)
        path = "repos/#{@repository}/rules/branches/#{URI.encode_uri_component(branch)}"
        stdout, stderr, status = @runner.call(['gh', 'api', "#{path}?per_page=#{RULES_PAGE}"], stdin_data: '')
        failed = !status.exitstatus.zero?
        return [] if failed && "#{stdout}#{stderr}".match?(PLAN_WITHOUT_RULESETS)
        raise Error.from_gh("gh api #{path} failed (exit #{status.exitstatus}).", stderr) if failed

        status_check_contexts(parse_json(stdout))
      end

      def status_check_contexts(rules)
        raise Error, 'GitHub branch rules response must be an array.' unless rules.is_a?(Array)
        raise Error, "GitHub returned #{RULES_PAGE} branch rules; refusing to read a truncated set." if
          rules.size >= RULES_PAGE

        rules.select { |rule| rule.is_a?(Hash) && rule['type'] == 'required_status_checks' }.flat_map do |rule|
          rule_contexts(rule.dig('parameters', 'required_status_checks'))
        end
      end

      # A rule whose checks cannot be read must not count as requiring nothing.
      def rule_contexts(checks)
        contexts = Array(checks).map { |check| check['context'] if check.is_a?(Hash) }
        return contexts if checks.is_a?(Array) && contexts.all? { |context| readable_context?(context) }

        raise Error, 'GitHub returned a required_status_checks rule without readable check names.'
      end

      def readable_context?(context) = context.is_a?(String) && !context.empty?
    end
  end
end
