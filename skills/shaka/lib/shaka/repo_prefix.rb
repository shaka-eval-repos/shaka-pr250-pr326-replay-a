# frozen_string_literal: true

require_relative 'error'

module Shaka
  # Presentation prefix for a repository. It grants no ownership or merge authority.
  class RepoPrefix
    PATTERN = /\A[A-Z0-9]{1,6}\z/

    def self.valid?(value)
      value.is_a?(String) && PATTERN.match?(value)
    end

    def self.validate!(value, label: 'repo_prefix')
      raise Error, "#{label} must be 1–6 uppercase ASCII letters or digits" unless valid?(value)

      value
    end

    def self.fallback(repository_name)
      name = repository_name.to_s.delete_suffix('.git')
      segments = alphanumeric_segments(name)
      raise Error, 'repository name is missing for prefix fallback' if segments.empty?

      prefix = segments.length == 1 ? segments.first[0, 4] : segments.map { |segment| segment[0] }.join
      validate!(prefix.upcase, label: 'prefix fallback')
    end

    def self.alphanumeric_segments(name)
      name.split(/[-_ ]/).map { |segment| segment.gsub(/[^A-Za-z0-9]/, '') }.reject(&:empty?).first(6)
    end
    private_class_method :alphanumeric_segments

    def self.display(configured:, repository_name:)
      if configured.nil?
        { 'prefix' => fallback(repository_name), 'source' => 'fallback' }
      else
        { 'prefix' => validate!(configured), 'source' => 'seam' }
      end
    end
  end
end
