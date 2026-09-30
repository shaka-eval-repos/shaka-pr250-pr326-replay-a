# frozen_string_literal: true

require 'uri'
require_relative '../error'
require_relative 'text'

module Shaka
  # Renders the links a reader needs before any description section.
  module PublicationLinks
    WALKTHROUGH_URL = %r{\Ahttps://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/\d+#pullrequestreview-\d+\z}
    UNPUBLISHED = '_Not published yet._'

    module_function

    # A published walkthrough shares its line with the deployment; the placeholder keeps its own.
    def top(content)
      walkthrough = walkthrough(content['walkthrough'])
      deployment = deployment(content['deployment'])
      return [walkthrough] unless deployment
      return [walkthrough, deployment] if walkthrough == UNPUBLISHED

      ["#{walkthrough} · #{deployment}"]
    end

    # Required so a deployable repository cannot silently omit its preview; `none` opts out.
    def deployment(url)
      url = PublicationText.single_line(url.is_a?(String) ? url.strip : url, 'deployment')
      return if url == 'none'
      raise Error, 'Publication deployment must be an https URL or none.' unless https_url?(url)

      # Angle brackets keep a `)` in the URL from ending the Markdown link early.
      "[Deployment](<#{url}>)"
    end

    def https_url?(url)
      uri = URI.parse(url)
      # Userinfo would publish credentials in a public PR body.
      uri.is_a?(URI::HTTPS) && !uri.host.to_s.empty? && uri.userinfo.nil?
    rescue URI::InvalidURIError
      false
    end

    def walkthrough(url)
      return UNPUBLISHED if url.nil? || (url.is_a?(String) && url.strip.empty?)

      url = PublicationText.single_line(url.is_a?(String) ? url.strip : url, 'walkthrough')
      unless url.match?(WALKTHROUGH_URL)
        raise Error, 'Publication walkthrough must be a GitHub pull request review URL.'
      end

      "[Code Walkthrough](#{url})"
    end
  end
end
