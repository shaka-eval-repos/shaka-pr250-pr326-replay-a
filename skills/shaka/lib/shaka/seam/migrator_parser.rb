# frozen_string_literal: true

require 'optparse'
require_relative 'policy_options'

module Shaka
  class Seam
    # CLI flags for seam migrate. Planning is default; apply is explicit.
    module MigratorParser
      include PolicyOptions

      private

      def parse!
        parser.parse!(@arguments)
        raise OptionParser::InvalidArgument, parser.to_s unless @arguments.empty?
        return help(parser) if @options[:help]

        require_migrate_options!
      end

      def parser
        OptionParser.new do |flags|
          flags.banner = 'Usage: shaka seam migrate --root DIR --from-ref SHA [--plan | --apply]'
          add_required_flags(flags)
          add_review_flags(flags)
          add_merge_flag(flags)
          flags.on('-h', '--help', 'Show usage') { @options[:help] = true }
        end
      end

      def add_required_flags(flags)
        flags.on('--root DIR', 'Repository root') { |value| @options[:root] = value }
        flags.on('--from-ref REF', 'Immutable predecessor default-branch commit') do |value|
          @options[:from_ref] = value
        end
        flags.on('--plan', 'Write nothing (default)') { @options[:plan] = true }
        flags.on('--apply', 'Write the classified seam after a successful preflight') { @options[:apply] = true }
      end

      def require_migrate_options!
        raise OptionParser::InvalidArgument, 'cannot combine --plan with --apply' if @options[:plan] && @options[:apply]
        raise OptionParser::InvalidArgument, '--root is required' unless @options[:root]
        raise OptionParser::InvalidArgument, '--from-ref is required' unless @options[:from_ref]
      end

      def add_review_flags(flags)
        add_review_policy_flag(flags)
        add_ci_review_job_flag(flags)
        reject_retired_review_flags(flags)
      end

      def add_review_policy_flag(flags)
        flags.on('--review-policy MODE', %w[always meaningful_changes none],
                 'Explicit review.required when the predecessor cannot establish it') do |value|
          @options[:review_policy] = value
        end
      end

      def add_merge_flag(flags)
        flags.on('--merge-preference MODE', %w[ask auto],
                 'Explicit merge.preference when the predecessor cannot establish it') do |value|
          @options[:merge_preference] = value
        end
      end

      def help(parser)
        puts parser
        @options[:help] = true
      end
    end
  end
end
