# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'error'
require_relative 'publication/publication'

module Shaka
  # Renders the model checkpoint after the agent has assessed and selected settings.
  class Recommendation
    FIELDS = %w[value scope risk model effort reason].freeze

    def self.run(arguments)
      path = content_path(arguments)
      return 0 unless path

      puts new(content(path)).render
      0
    rescue OptionParser::ParseError, JSON::ParserError, SystemCallError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def self.content_path(arguments)
      options = {}
      parser = option_parser(options)
      parser.parse!(arguments)
      puts parser if options[:help]
      return if options[:help]

      raise OptionParser::InvalidArgument, parser.to_s unless arguments.empty? && options[:path]

      options.fetch(:path)
    end

    def self.option_parser(options)
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka recommendation --content-file PATH'
        flags.on('--content-file PATH', 'Recommendation content as JSON') { |value| options[:path] = value }
        flags.on('-h', '--help', 'Show usage') { options[:help] = true }
      end
    end

    def self.content(path)
      parsed = JSON.parse(File.read(path, encoding: 'UTF-8'))
      raise Error, 'Recommendation content must be an object.' unless parsed.is_a?(Hash)

      parsed
    end

    private_class_method :content_path, :option_parser, :content

    def initialize(content)
      @content = content
    end

    def render
      FIELDS.map do |field|
        "#{field.capitalize}: #{PublicationText.single_line(@content[field], "recommendation #{field}")}\n"
      end.join
    end
  end
end
