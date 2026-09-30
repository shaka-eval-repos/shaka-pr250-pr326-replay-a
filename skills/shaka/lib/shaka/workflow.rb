# frozen_string_literal: true

require 'optparse'
require_relative 'error'
require_relative 'workflow_config'

module Shaka
  # Renders the validated workflow for an agent host.
  class Workflow
    PACKAGE_ROOT = File.expand_path('../../..', File.dirname(WorkflowConfig::PATH))
    TOKENS = {
      'package_root' => PACKAGE_ROOT
    }.freeze

    def self.run(arguments)
      new(arguments).run
    rescue OptionParser::ParseError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def initialize(arguments)
      @arguments = arguments.dup
    end

    def run
      parser = option_parser
      parser.parse!(@arguments)
      return help(parser) if @help

      raise OptionParser::InvalidArgument, parser.to_s unless @arguments.empty?

      puts render(WorkflowConfig.load)
      0
    end

    private

    def option_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka workflow'
        flags.on('-h', '--help', 'Show usage') { @help = true }
      end
    end

    def help(parser)
      puts parser
      0
    end

    def render(config)
      sections = config.fetch('phases').each_with_index.map { |phase, index| render_phase(phase, index + 1) }
      ["# #{config.fetch('title')}", expand(config.fetch('purpose')),
       "Workflow source: `#{WorkflowConfig::PATH}`", *sections,
       "## Always\n\n#{expand(config.fetch('always')).strip}",
       "## Code quality\n\n#{expand(config.fetch('code_quality')).strip}"].join("\n\n")
    end

    def render_phase(phase, number)
      "## #{number}. #{phase.fetch('title')}\n\n#{expand(phase.fetch('body')).strip}\n\n" \
        "**Done when:** #{expand(phase.fetch('done_when')).strip}"
    end

    def expand(text)
      expanded = text.gsub(/\{\{([^{}]+)\}\}/) do
        TOKENS.fetch(Regexp.last_match(1)) { raise Error, 'workflow.yml contains an unknown template token' }
      end
      raise Error, 'workflow.yml contains an unknown template token' if expanded.include?('{{')

      expanded
    end
  end
end
