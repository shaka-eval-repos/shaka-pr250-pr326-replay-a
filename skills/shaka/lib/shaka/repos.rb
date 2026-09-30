# frozen_string_literal: true

require 'json'
require 'optparse'
require 'uri'
require_relative 'error'
require_relative 'git_origin'
require_relative 'prefix'
require_relative 'repos/home'

module Shaka
  # Rebuildable install-local index of repository prefixes. Not an authority source.
  class Repos
    def self.run(arguments)
      new(arguments).run
    rescue OptionParser::ParseError, SystemCallError, Shaka::Error, Psych::Exception => e
      warn "shaka: #{e.message}"
      1
    end

    def initialize(arguments)
      @arguments = arguments.dup
      @options = {}
    end

    def run
      parser = option_parser
      parser.parse!(@arguments)
      return help(parser) if @options[:help]

      operation = @arguments.shift
      raise OptionParser::InvalidArgument, parser.to_s unless valid?(operation)

      operation == 'add' ? add : refresh
    end

    private

    def valid?(operation)
      %w[add refresh].include?(operation) && @arguments.empty? &&
        (operation == 'refresh' || @options.key?(:root))
    end

    def add
      puts JSON.pretty_generate({ 'roots' => home.add(@options.fetch(:root)) })
      0
    end

    def refresh
      catalog, skipped = catalog_payload
      home.write_catalog(catalog)
      puts JSON.pretty_generate(catalog)
      skipped_status = skipped ? 1 : 0
      [skipped_status, report_duplicates(catalog.fetch('duplicate_prefixes'))].max
    end

    def catalog_payload
      skipped = false
      repositories = []
      home.roots_list.each do |configured|
        repositories << entry(home.resolve(configured))
      rescue SystemCallError, Shaka::Error => e
        warn "shaka: skipping #{configured}: #{e.message}"
        skipped = true
      end
      repositories.sort_by! { |row| row.fetch('identity') }
      [{ 'version' => 1, 'repositories' => repositories, 'duplicate_prefixes' => duplicates(repositories) }, skipped]
    end

    def entry(root)
      origin = GitOrigin.from(root:)
      display = Prefix.new(root: root).call
      { 'identity' => origin.fetch(:identity), 'url' => GitOrigin.canonical_url(origin.fetch(:origin)),
        'root' => root, 'prefix' => display.fetch('prefix'), 'prefix_source' => display.fetch('source') }
    end

    def duplicates(repositories)
      repositories.group_by { |row| row.fetch('prefix') }.each_with_object({}) do |(prefix, rows), collected|
        keys = rows.map { |row| collision_key(row) }.uniq
        next unless keys.length > 1

        collected[prefix] = keys
      end
    end

    def collision_key(row)
      uri = catalog_uri(row)
      default = uri.scheme == 'ssh' ? 22 : uri.default_port
      host = uri.port && uri.port != default ? "#{uri.host}:#{uri.port}" : uri.host
      "#{host.downcase}/#{collision_identity(uri, row)}"
    end

    def catalog_uri(row)
      URI(row.fetch('url'))
    rescue URI::InvalidURIError
      raise Error, "Cannot parse catalog URL for #{row.fetch('identity')}"
    end

    def collision_identity(_uri, row)
      row.fetch('identity').downcase
    end

    def report_duplicates(duplicates)
      return 0 if duplicates.empty?

      duplicates.each { |prefix, identities| warn "shaka: duplicate repo_prefix #{prefix}: #{identities.join(', ')}" }
      1
    end

    def home
      @home ||= Home.new(File.expand_path(home_path))
    end

    def home_path
      @options.fetch(:home, ENV.fetch('SHAKA_HOME', File.join(Dir.home, '.shaka')))
    end

    def option_parser
      OptionParser.new do |flags|
        flags.banner = "Usage: shaka repos add --root DIR\n       shaka repos refresh"
        flags.on('--root DIR', 'Repository to register') { |value| @options[:root] = value }
        flags.on('--home DIR', 'Install-local Shaka home (default: $SHAKA_HOME or ~/.shaka)') do |value|
          @options[:home] = value
        end
        flags.on('-h', '--help', 'Show usage') { @options[:help] = true }
      end
    end

    def help(parser)
      puts parser
      0
    end
  end
end
