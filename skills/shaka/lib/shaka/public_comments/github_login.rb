# frozen_string_literal: true

module Shaka
  module PublicComments
    # One GitHub-login shape for config and public author checks.
    module GitHubLogin
      PATTERN = /\A(?=.{1,39}\z)[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\z/

      def self.valid(logins)
        logins.uniq.select { |login| login.is_a?(String) && login.match?(PATTERN) }
      end
    end
  end
end
