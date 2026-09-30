# frozen_string_literal: true

module Shaka
  # Dispositions target an explicit round when a batch has several reviewers.
  module LocalReviewRecord
    private

    def record(parser)
      raise OptionParser::InvalidArgument, parser.to_s unless
        @arguments.empty? && @options[:ledger] && @options[:content_file]

      ledger = LocalReviewLedger.new(@options[:ledger])
      number = ledger.record!(JSON.parse(File.read(@options[:content_file], encoding: 'UTF-8')),
                              number: @options[:round])
      puts JSON.pretty_generate('ledger' => ledger.path, 'round' => number)
      0
    end

    def record_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka review record --ledger PATH --content-file PATH [--round N]'
        flags.on('--round N', Integer) { |value| @options[:round] = positive_round(value) }
        flags.on('--ledger PATH') { |value| @options[:ledger] = value }
        flags.on('--content-file PATH') { |value| @options[:content_file] = value }
        flags.on('-h', '--help') { @options[:help] = true }
      end
    end

    def positive_round(value)
      raise OptionParser::InvalidArgument, '--round must be a positive integer' unless value.positive?

      value
    end
  end
end
