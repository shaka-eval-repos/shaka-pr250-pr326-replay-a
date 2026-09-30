# frozen_string_literal: true

require_relative 'error'

module Shaka
  # Matches the audited quotes against the workflow they claim to quote.
  #
  # An audit that drifts from the procedure is worse than none, so this fails both ways: on a
  # quote the workflow no longer contains, and on one of MARKER's four forms appearing outside
  # every classified quote. A rule phrased another way is caught by review, not here.
  class EnforcementCoverage
    # The four imperative and prohibitive forms workflow.yml uses to state a rule.
    MARKER = /\b(?:never|must|do not|only when)\b/i

    # Phase bodies carry their completion condition, and every standing field states rules too,
    # `purpose` included. Fenced command listings are dropped: they are syntax, not prose.
    STANDING = %w[purpose always code_quality].freeze

    def self.sections(workflow)
      sections = workflow.fetch('phases').to_h do |phase|
        [phase.fetch('id'), "#{phase.fetch('body')} #{phase.fetch('done_when')}"]
      end
      STANDING.each { |field| sections[field] = workflow.fetch(field) }
      sections.transform_values { |text| normalize(text) }
    end

    def self.normalize(text) = text.gsub(/```.*?```/m, ' ').gsub(/\s+/, ' ').strip

    def initialize(workflow)
      @sections = self.class.sections(workflow)
    end

    def check(rules)
      located = @sections.transform_values { [] }
      rules.each do |rule|
        taken = located.fetch(section(rule))
        span = locate(rule)
        overlapping!(rule, taken, span)
        taken << span
      end
      complete!(located)
    end

    private

    def section(rule)
      id = rule['phase']
      raise Error, "rule #{rule['id']} names no workflow section" unless @sections.key?(id)

      id
    end

    # One unambiguous span per quote, so the completeness check can trust its offsets.
    def locate(rule)
      text = @sections.fetch(section(rule))
      quote = self.class.normalize(rule.fetch('quote'))
      at = text.index(quote)
      raise Error, "rule #{rule['id']} quotes text the #{rule['phase']} section does not contain" unless at
      raise Error, "rule #{rule['id']} quotes #{rule['phase']} text that appears twice" if text.index(quote, at + 1)

      [at, at + quote.length]
    end

    # Two entries over one sentence would answer the same question twice, and nothing would
    # say which answer to believe.
    def overlapping!(rule, taken, (from, to))
      return unless taken.any? { |start, finish| from < finish && start < to }

      raise Error, "rule #{rule['id']} classifies #{rule['phase']} text another rule already covers"
    end

    # A marked passage added to workflow.yml fails here until an entry classifies it.
    def complete!(located)
      @sections.each do |id, text|
        text.to_enum(:scan, MARKER).each do
          at = Regexp.last_match.begin(0)
          next if located.fetch(id).any? { |from, to| at >= from && at < to }

          raise Error, "enforcement.yml classifies no rule for #{id}: \"#{text[at, 60]}\""
        end
      end
    end
  end
end
