# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative '../github'
require_relative '../ci_review_wait'
require_relative '../pr_watch'
require_relative '../trusted_config_source'

module Shaka
  class PrWatch
    # The watcher is a separate command so its own flags cannot change ordinary `pr` reads.
    module Command
      module_function

      def run(arguments)
        options, parser = parse(arguments)
        return help(parser) if options[:help]

        require_target!(arguments, options)
        reason = watcher(arguments, options).call
        puts "SHAKA_WAKE #{reason}"
        0
      rescue OptionParser::ParseError, Error, SystemCallError, KeyError, JSON::ParserError => e
        puts "SHAKA_WAKE error: #{e.message.gsub(/[\r\n]+/, ' ')}"
        1
      end

      def watcher(arguments, options)
        seam = TrustedConfigSource.from_ref(root: options[:root] || Dir.pwd, ref: options[:ref])
        settings = watch_settings(options, seam)
        PrWatch.new(GitHub.new(*arguments), head: options[:head],
                                            ci_jobs: review_jobs(options, seam), settings:)
      end

      def review_jobs(options, seam)
        return Array(seam.review['ci_review_jobs']) unless options[:ci_review_not_required]

        unless seam.review['required'] == 'meaningful_changes'
          raise Error, '--ci-review-not-required needs review.required: meaningful_changes.'
        end

        []
      end

      def watch_settings(options, seam)
        settings = options.slice(:interval, :timeout, :settle)
        settings[:ci_review_wait] = CiReviewWait.effective(
          seam: seam.review['ci_review_wait'], override: options[:ci_review_wait]
        )
        settings[:seam_required_checks] = seam.merge['required_checks']
        settings[:baseline] = baseline(options) if options[:baseline]
        settings
      end

      def baseline(options)
        packet = JSON.parse(File.read(options[:baseline], encoding: 'UTF-8'))
        valid = packet.is_a?(Hash) && packet['head'] == options[:head]
        raise Error, 'Comment baseline is not for the expected PR head.' unless valid

        packet
      end

      def parse(arguments)
        options = {}
        parser = option_parser(options)
        parser.parse!(arguments)
        [options, parser]
      end

      def option_parser(options)
        OptionParser.new do |flags|
          flags.banner = 'Usage: shaka pr watch OWNER/REPO NUMBER --head SHA --ref SHA [options]'
          %w[head ref root].each { |name| flags.on("--#{name} VALUE") { |value| options[name.to_sym] = value } }
          %w[interval timeout settle].each do |name|
            flags.on("--#{name} SECONDS", Integer) { |value| options[name.to_sym] = value }
          end
          review_wait_option(flags, options)
          baseline_option(flags, options)
          flags.on('-h', '--help') { options[:help] = true }
        end
      end

      def review_wait_option(flags, options)
        flags.on('--ci-review-wait MODE', CiReviewWait::VALUES) { |value| options[:ci_review_wait] = value }
        flags.on('--ci-review-not-required') { options[:ci_review_not_required] = true }
      end

      def baseline_option(flags, options)
        flags.on('--baseline PATH', 'Saved shaka comments JSON for the same head') do |value|
          options[:baseline] = value
        end
      end

      def require_target!(arguments, options)
        return if arguments.length == 2 && options[:head] && options[:ref]

        raise Error, 'Expected OWNER/REPO NUMBER and --head SHA --ref SHA.'
      end

      def help(parser)
        puts parser
        0
      end
    end
  end
end
