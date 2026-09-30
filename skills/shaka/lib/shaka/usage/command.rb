# frozen_string_literal: true

require 'optparse'
require_relative '../error'
require_relative 'claude_usage'
require_relative 'codex_usage'
require_relative 'cost_estimate'
require_relative 'cursor_usage'
require_relative 'opencode_usage'
require_relative 'pi_usage'
require_relative 'json_report'
require_relative 'usage_records'
require_relative 'usage_errors'
require_relative 'usage_table'
require_relative 'usage_turns'
require_relative 'usage_identity'
require_relative 'since_time'
require_relative 'options'

module Shaka
  # Read-only reporting of per-response usage records from a supported host.
  class Usage
    include UsageTable
    include UsageTurns
    include UsageIdentity
    include UsageJsonReport
    include UsageSinceTime
    extend UsageOptions

    SETTING_LABELS = ['Provider', 'Configured model', 'Routed model', 'Effort'].freeze
    METRIC_FIELDS = [
      ['Input', 'input_tokens'],
      ['Cached input', 'cached_input_tokens'],
      ['Output', 'output_tokens'],
      ['Reasoning output', 'reasoning_output_tokens'],
      ['Cache writes', 'cache_write_input_tokens'],
      ['Native total', 'total_tokens']
    ].freeze
    READERS = { 'codex' => CodexUsage, 'claude-code' => ClaudeUsage, 'cursor' => CursorUsage,
                'opencode' => OpencodeUsage, 'pi' => PiUsage }.freeze
    HOST_CONTEXT = { 'codex' => 'CODEX_THREAD_ID', 'claude-code' => 'CLAUDE_CODE_SESSION_ID',
                     'cursor' => 'CURSOR_CONVERSATION_ID', 'opencode' => 'OPENCODE_SESSION_ID',
                     'pi' => 'PI_CODING_AGENT' }.freeze

    def self.run(arguments)
      options = { files: [], turns: [], host: detected_host, format: 'markdown' }
      parser(options).parse!(arguments)
      puts parser(options) if options[:help]
      return 0 if options[:help]

      raise OptionParser::InvalidArgument unless arguments.empty? && valid_mapping?(options)

      new(options).print_report
    rescue OptionParser::ParseError, Error => e
      warn UsageErrors.message(e)
      1
    end

    def self.parser(options)
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka usage --commit SHA[,SHA] --contribution NAME [options]'
        source_options(flags, options)
        UsageJsonReport.format_option(flags, options)
        flags.on('--commit SHA', 'Affected full commit SHAs, comma separated') { |v| options[:commit] = v }
        flags.on('--contribution NAME', 'Contribution category (see guide)') { |v| options[:contribution] = v }
        flags.on('--rate-root DIR', 'Implementation rate-card checkout') { |value| options[:rate_root] = value }
        flags.on('-h', '--help') { options[:help] = true }
      end
    end

    def self.detected_host
      found = HOST_CONTEXT.select { |host, variable| host == 'pi' ? ENV[variable] == 'true' : ENV.key?(variable) }.keys
      found.size > 1 ? nil : found.first || 'codex'
    end

    def initialize(options)
      @options = options
      reader = READERS.fetch(options[:host])
      @inferred = options[:files].empty?
      @options[:files] = reader.discover if @inferred
      all_turns = @options[:all_turns] || @options.key?(:since_time)
      @source = reader.new(@options[:files], @options[:turns], all_turns:)
      load_responses
    end

    def report = "#{UsageRecords.begin_mark(record_identity)}\n#{report_body}#{UsageRecords::END_MARK}\n"

    def report_body
      <<~MARKDOWN
        #{CostEstimate.new(cost_responses, inclusive_input: @source.class::INCLUSIVE_INPUT,
                                           rate_card: selected_rate_card).report.rstrip}

        #{reviewer_coverage}
        Native usage is PARTIAL. #{count}. Scope: #{turn_scope}.

        <details>
        <summary>Token detail</summary>

        #{@options[:commit]} / #{@options[:contribution]}
        SHARED source interval: #{interval}. Snapshot through the last observed response.
        Source selection: #{@inferred ? 'host context' : 'explicit files'}.
        #{@source.class::HOST} source versions: #{versions}.
        #{@source.class::NOTE}

        #{rows}

        </details>
      MARKDOWN
    end

    private

    def load_responses
      @selected_responses = @source.responses.dup
      select_since_time if @options[:since_time]
      @responses = @selected_responses.values
    end

    def selected_rate_card
      RateCard.select(contribution: @options[:contribution], explicit_root: @options[:rate_root])
    end

    def turn_scope
      return 'all turns in selected sources' if @options[:all_turns]
      if @options[:since_time]
        return "responses at or after #{@options[:since_time]} (whole-second sources include the cutoff second)"
      end

      @options[:turns].empty? ? @source.class::LATEST_SCOPE : 'explicitly selected turns'
    end

    def count
      @responses.empty? ? 'Responses: UNKNOWN (no readable per-response records)' : "#{@responses.size} responses"
    end

    def versions
      @source.versions.empty? ? 'UNKNOWN' : @source.versions.uniq.map { |version| safe(version) }.join(', ')
    end

    def interval
      from, to = interval_fields.values_at('from', 'to')
      from == 'UNKNOWN' ? 'UNKNOWN' : "#{from} through #{to}"
    end

    def safe(value)
      value.is_a?(String) && value.match?(/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,79}\z/) ? value : 'UNKNOWN'
    end
  end
end
