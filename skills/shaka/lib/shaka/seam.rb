# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'error'
require_relative 'repository_config'
require_relative 'seam/check_report'
require_relative 'seam/initializer'
require_relative 'seam/migrator'
require_relative 'seam/upgrader'
require_relative 'seam/pointer'
require_relative 'seam/policy_options'
require_relative 'seam/private_command'
require_relative 'configuration'

module Shaka
  # Validates the machine-readable repository boundary.
  class Seam
    include PolicyOptions

    def self.run(arguments)
      new(arguments).run
    rescue OptionParser::ParseError, SystemCallError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def initialize(arguments)
      @arguments = arguments.dup
      @options = {}
    end

    def run
      return Migrator.run(@arguments) if @arguments.first == 'migrate'
      return Upgrader.run(@arguments) if @arguments.first == 'upgrade'
      return PrivateCommand.run(@arguments.drop(1)) if @arguments.first == 'private'

      parser = option_parser
      parser.parse!(@arguments)
      return help(parser) if @options[:help]

      operation = @arguments.shift
      validate_operation(operation, parser)
      render_config(operation)
    end

    private

    def validate_operation(operation, parser)
      raise OptionParser::InvalidArgument, parser.to_s unless known_operation?(operation)
      return Pointer.refuse_foreign_options(@options) if operation == 'pointer'

      operation == 'check' ? validate_check_options : validate_init_options
    end

    def known_operation?(operation) = %w[check init pointer].include?(operation) && @arguments.empty?

    def validate_check_options
      init_keys = %i[base_branch setup_command validate_command test_command review_policy ci_review_jobs
                     merge_preference required_checks]
      raise OptionParser::InvalidArgument, 'init options do not apply to check' if @options.keys.intersect?(init_keys)
      raise OptionParser::InvalidArgument, '--local cannot be combined with --ref' if local? && @options.key?(:ref)
    end

    def validate_init_options
      raise OptionParser::InvalidArgument, '--ref does not apply to init' if @options.key?(:ref)
      raise OptionParser::InvalidArgument, '--local does not apply to init' if local?
    end

    def render_config(operation)
      return Pointer.emit if operation == 'pointer'
      return CheckReport.emit(Initializer.new(root:, options: @options).call.to_h) if operation == 'init'

      warn "shaka: #{CheckReport::IMPLICIT_DIAGNOSTIC}" if implicit_local?
      CheckReport.emit(check_report.to_h)
    end

    def check_report
      config = Configuration.trusted(root:, ref: @options[:ref])
      return CheckReport.trusted(config, ref: @options[:ref]) if @options.key?(:ref)

      CheckReport.local(config)
    end

    def local? = @options[:local] == true

    def implicit_local? = !local? && !@options.key?(:ref)

    def option_parser
      OptionParser.new do |flags|
        flags.banner = usage
        add_common_options(flags)
        add_init_options(flags)
        flags.on('-h', '--help', 'Show usage') { @options[:help] = true }
      end
    end

    def usage
      "Usage: shaka seam check [--root DIR] [--local | --ref REF]\n       " \
        "shaka seam init --root DIR [options]\n       " \
        "shaka seam migrate --root DIR --from-ref SHA [--plan | --apply]\n       " \
        "shaka seam upgrade --root DIR [--apply --digest PREVIEW_DIGEST | --recover]\n       " \
        "shaka seam private setup|inspect|list|restore --root DIR [options]\n       " \
        'shaka seam pointer'
    end

    def add_common_options(flags)
      flags.on('--root DIR', 'Repository root (default: current directory)') { |value| @options[:root] = value }
      flags.on('--local', 'Validate the candidate checkout; grants no policy or merge authority') do
        @options[:local] = true
      end
      flags.on('--ref REF', 'Read policy from this trusted Git commit') { |value| @options[:ref] = value }
    end

    def add_init_options(flags)
      flags.on('--base-branch BRANCH', 'Base branch when it is not the default branch') do |value|
        @options[:base_branch] = value
      end
      add_command_options(flags)
      add_policy_options(flags)
    end

    def add_command_options(flags)
      %w[setup validate test].each do |name|
        flags.on("--#{name}-command COMMAND", "Simple argv command for #{name}") do |value|
          @options[:"#{name}_command"] = value
        end
      end
    end

    def help(parser)
      puts parser
      0
    end

    def root
      File.realpath(@options.fetch(:root, Dir.pwd))
    end
  end
end
