# frozen_string_literal: true

require 'optparse'
require_relative 'enforcement_config'
require_relative 'enforcement_coverage'
require_relative 'error'

module Shaka
  # Reports what enforces each rule the packaged workflow states with never, must, do not,
  # or only when. Whether an entry's answer is true is for a human to review; this renders it.
  class Enforcement
    QUESTION = 'Each row answers one question: if an agent ignores this rule, does anything fail?'
    CODE_LEGEND = '- `code` — a `shaka` command refuses the action when it runs. A merge can be ' \
                  "the maintainer's own GitHub click, which no command sees, so each row says " \
                  'what holds there.'
    LEGEND = "#{CODE_LEGEND}\n" \
             "- `reported` — a command surfaces the violation; the agent can still proceed.\n" \
             "- `github` — a repository setting refuses it.\n" \
             '- `agent` — nothing checks it; the note says what is missing.'.freeze
    SCOPE = 'The scan behind this audit finds the rules workflow.yml states with never, ' \
            'must, do not, or only when; an entry may classify a rule stated another way, ' \
            'but nothing requires one. It reads packaged text alone, so a `github` row ' \
            'describes the repository that ships this audit and nothing here confirms that ' \
            'setting is still active.'
    HEADER = "| Rule | Enforced by | What backs it |\n| --- | --- | --- |"
    # Package-relative: the report is pasted into issues, and an absolute path names a machine.
    SOURCE = 'skills/shaka/config/enforcement.yml'

    # Folded YAML carries newlines, and a stray pipe would split the row it belongs in. One
    # pass over both characters, so a backslash cannot arrive already escaped and slip a pipe
    # through behind it.
    def self.cell(text) = EnforcementCoverage.normalize(text).gsub(/[\\|]/) { |char| "\\#{char}" }

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

      workflow = WorkflowConfig.load
      puts render(EnforcementConfig.load(workflow:).fetch('rules'), workflow)
      0
    end

    private

    def option_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka enforcement'
        flags.on('-h', '--help', 'Show usage') { @help = true }
      end
    end

    def help(parser)
      puts parser
      0
    end

    def render(rules, workflow)
      titles = section_titles(workflow)
      sections = titles.filter_map do |id, title|
        listed = rules.select { |rule| rule['phase'] == id }
        "## #{title}\n\n#{HEADER}\n#{listed.map { |rule| row(rule) }.join("\n")}" unless listed.empty?
      end
      ['# Workflow rule enforcement', "Audit source: `#{SOURCE}`",
       tally(rules), QUESTION, LEGEND, SCOPE, *sections].join("\n\n")
    end

    # Titled from the same list the coverage check scans, so a new standing field cannot be
    # audited into a section this report would then leave out.
    def section_titles(workflow)
      titles = workflow.fetch('phases').to_h { |phase| [phase.fetch('id'), phase.fetch('title')] }
      EnforcementCoverage::STANDING.each { |field| titles[field] = field.tr('_', ' ').capitalize }
      titles
    end

    def tally(rules)
      counts = rules.group_by { |rule| rule.fetch('enforced_by') }.transform_values(&:length)
      "#{rules.length} audited rules: #{counts.fetch('code', 0)} refused by a command, " \
        "#{counts.fetch('reported', 0)} reported by one, #{counts.fetch('github', 0)} refused by GitHub, " \
        "and #{counts.fetch('agent', 0)} enforced by nothing but the agent."
    end

    # A quote locates the rule in the workflow; where a span is not a readable sentence on
    # its own, `rule` states it. Without that, half of "Never A or B" would read as do B.
    def row(rule)
      backing = rule['detector'] || rule.fetch('note')
      stated = rule['rule'] || rule.fetch('quote')
      "| #{self.class.cell(stated)} | #{rule.fetch('enforced_by')} | #{self.class.cell(backing)} |"
    end
  end
end
