# frozen_string_literal: true

require 'open3'
require_relative 'error'

module Shaka
  # Parses a Git origin URL into owner/name without calling GitHub.
  module GitOrigin
    URI_HOST_PATH = %r{\A(https?|ssh)://(?:[^/]*@)?([^/:@]+)(?::(\d+))?/(.+)}
    SCP_HOST_PATH = /\A(?:[^@]+@)?([^:@]+):(.+)/

    module_function

    def from(root:)
      url, error, status = Open3.capture3('git', '-C', root, 'remote', 'get-url', 'origin')
      raise Error, "Cannot read origin for #{root}: #{error.strip}" unless status.success?

      parsed(url.strip)
    end

    def repository_name(root:)
      from(root:).fetch(:name)
    rescue Error
      File.basename(File.realpath(root))
    end

    def repository_name_from(url) = parsed(url).fetch(:name)

    def identity(url) = parsed(url).fetch(:identity)

    def canonical_url(url)
      parsed_url = parsed(url)
      identity = parsed_url.fetch(:identity)
      return "https://github.com/#{identity}" if github_https?(parsed_url)

      scheme = parsed_url[:scheme]
      host = authority(parsed_url)
      return "ssh://#{host}/#{identity}" unless scheme

      "#{scheme}://#{host}/#{identity}"
    end

    def parsed(url)
      origin = url.strip
      uri_fields(origin) || scp_fields(origin) || parse_error(origin)
    end
    private_class_method :parsed

    def uri_fields(origin)
      match = URI_HOST_PATH.match(origin)
      host = host_from(match&.[](2))
      return unless host

      path = repository_path(match[4], origin)
      { origin:, scheme: match[1], host:, port: match[3], identity: path, name: File.basename(path) }
    end
    private_class_method :uri_fields

    def scp_fields(origin)
      match = SCP_HOST_PATH.match(origin)
      host = host_from(match&.[](1))
      return unless host

      path = repository_path(match[2], origin)
      { origin:, scheme: nil, host:, port: nil, identity: path, name: File.basename(path) }
    end
    private_class_method :scp_fields

    def host_from(raw)
      host = raw.to_s.sub(/\.+\z/, '')
      host if valid_host?(host)
    end
    private_class_method :host_from

    def valid_host?(host) = host.match?(/\A[A-Za-z0-9.-]+\z/)
    private_class_method :valid_host?

    def repository_path(raw, origin)
      path = raw.split(/[?#]/, 2).first&.delete_suffix('.git')
      return path if path&.match?(%r{\A[A-Za-z0-9._~-]+/[A-Za-z0-9._~-]+\z})

      parse_error(origin)
    end
    private_class_method :repository_path

    def github_https?(parsed_url)
      parsed_url.fetch(:host).casecmp?('github.com') && default_port?(parsed_url)
    end
    private_class_method :github_https?

    def default_port?(parsed_url)
      port = parsed_url[:port]
      return true if port.nil?

      port == { 'ssh' => '22', 'http' => '80', 'https' => '443' }.fetch(parsed_url[:scheme], nil)
    end
    private_class_method :default_port?

    def authority(parsed_url)
      host = parsed_url.fetch(:host).downcase
      default_port?(parsed_url) ? host : "#{host}:#{parsed_url[:port]}"
    end
    private_class_method :authority

    def parse_error(origin)
      raise Error, "Cannot parse owner/name from origin #{redacted_origin(origin)}"
    end
    private_class_method :parse_error

    def redacted_origin(origin)
      origin.to_s.split(/[?#]/, 2).first.sub(%r{\A((?:https?|ssh)://)[^/]*@}, '\1').sub(/\A(?:[^@]+@)+/, '')
    end
    private_class_method :redacted_origin
  end
end
