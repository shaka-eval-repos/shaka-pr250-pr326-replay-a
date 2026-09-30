# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require_relative 'upgrade_plan'
require_relative 'upgrader/apply'
require_relative 'upgrader/filesystem'
require_relative 'upgrader/recovery'
require_relative 'upgrader/recovery_completion'
require_relative 'upgrader/recovery_checks'

module Shaka
  class Seam
    # Moves a legacy candidate layout with an explicit preview and a recoverable journal.
    class Upgrader
      JOURNAL = 'shaka-upgrade-journal.json'

      include Apply
      include Filesystem
      include Recovery
      include RecoveryCompletion
      include RecoveryChecks

      def self.run(arguments)
        new(arguments).run
      rescue OptionParser::ParseError, SystemCallError, Shaka::Error, JSON::ParserError => e
        warn "shaka: #{e.message}"
        1
      end

      def self.journal_path(root)
        output, error, status = Open3.capture3('git', '-C', root, 'rev-parse', '--git-path', JOURNAL)
        raise Error, "Cannot locate Git upgrade journal: #{error.strip}" unless status.success?

        File.expand_path(output.strip, root)
      end

      def initialize(arguments)
        @arguments = arguments.dup
        @options = {}
      end

      def run
        parse_request!
        return 0 if @options[:help]

        @root = File.realpath(@options.fetch(:root))
        verify_git_root!
        dispatch
      end

      def parse_request!
        @arguments.shift if @arguments.first == 'upgrade'
        parser.parse!(@arguments)
        return if @options[:help]

        validate_request!
      end

      def validate_request!
        raise OptionParser::InvalidArgument, parser.to_s unless @arguments.empty? && @options[:root]

        validate_mode!
      end

      def validate_mode!
        raise OptionParser::InvalidArgument, '--apply requires --digest from preview' if missing_digest?
        raise OptionParser::InvalidArgument, '--digest requires --apply' if @options[:digest] && !@options[:apply]
        return unless @options[:apply] && @options[:recover]

        raise OptionParser::InvalidArgument,
              '--apply and --recover are exclusive'
      end

      def missing_digest? = @options[:apply] && !@options[:digest]

      def dispatch
        return recover if @options[:recover]
        return existing_journal if File.exist?(journal_path) || File.symlink?(journal_path)

        plan = UpgradePlan.new(@root)
        report = plan.build
        return apply(plan, report) if @options[:apply]

        puts JSON.generate(report)
        0
      end

      def existing_journal
        raise Error, "Interrupted upgrade at #{journal_path}; run --recover" if @options[:apply]

        journal_notice
      end

      private

      def parser
        OptionParser.new do |flags|
          flags.banner = 'Usage: shaka seam upgrade --root DIR [--apply --digest PREVIEW_DIGEST | --recover]'
          flags.on('--root DIR', 'Repository root') { |value| @options[:root] = value }
          add_mode_options(flags)
          flags.on('-h', '--help', 'Show usage') do
            puts flags
            @options[:help] = true
          end
        end
      end

      def add_mode_options(flags)
        flags.on('--apply', 'Apply the complete preview after a fresh preflight') { @options[:apply] = true }
        flags.on('--digest PREVIEW_DIGEST', 'Digest from the reviewed preview') { |value| @options[:digest] = value }
        flags.on('--recover', 'Restore files after an interrupted apply') { @options[:recover] = true }
      end

      def verify_git_root!
        output, error, status = Open3.capture3('git', '-C', @root, 'rev-parse', '--show-toplevel')
        raise Error, "Cannot identify repository root: #{error.strip}" unless status.success?

        git_root = output.delete_suffix("\n")
        raise Error, "--root must be the Git worktree root: #{git_root}" unless File.realpath(git_root) == @root
      end

      def journal_path = self.class.journal_path(@root)

      def journal_notice
        message = "Interrupted upgrade journal at #{journal_path}; run shaka seam upgrade --root #{@root} --recover, " \
                  'then preview again. Preserve any file edited since interruption and repair it manually.'
        puts JSON.generate('mode' => 'preview', 'status' => 'recovery_required', 'blockers' => [message])
        0
      end
    end
  end
end
