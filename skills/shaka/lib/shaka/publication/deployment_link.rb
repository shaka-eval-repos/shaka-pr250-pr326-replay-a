# frozen_string_literal: true

require_relative '../error'

module Shaka
  # Resolves `deployment: auto` from the GitHub Deployments API. Providers word their
  # PR comments differently, but a successful deployment status carries the same
  # `environment_url` that GitHub shows as "View deployment".
  module DeploymentLink
    AUTO = 'auto'
    PAGE = 100

    module_function

    def resolve(content, github)
      return content unless content['deployment'] == AUTO

      content.merge('deployment' => live_url(github, github.snapshot.fetch('headRefOid')) || 'none')
    end

    # Only the head commit counts, so a link never describes code the PR no longer holds.
    def live_url(github, head)
      deployments = github.api_list("repos/#{github.repository}/deployments?sha=#{head}&per_page=#{PAGE}")
      newest_first = deployments.sort_by { |deployment| deployment['created_at'].to_s }.reverse
      url = newest_first.lazy.filter_map { |deployment| success_url(github, deployment.fetch('id')) }.first
      # A full page may hide an older live deployment, so absence is unproven.
      if url.nil? && deployments.size >= PAGE
        raise Error, 'Too many deployments to resolve deployment: auto; supply the URL or none.'
      end

      url
    end

    def success_url(github, id)
      latest = github.api_list("repos/#{github.repository}/deployments/#{id}/statuses?per_page=1").first
      url = latest['environment_url'].to_s if latest && latest['state'] == 'success'
      url if url&.start_with?('https://')
    end
  end
end
