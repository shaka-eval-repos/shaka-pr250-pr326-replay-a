# frozen_string_literal: true

# Refuses a description or walkthrough whose rendered, visible prose is shaped as a wall of text.

require_relative 'error'
require_relative 'visible_prose'

module Shaka
  # Keeps visible prose short enough that the reader reviews the code instead of reading about it.
  class ProseLimits
    DEFAULTS = { 'max_sentence_words' => 35, 'max_paragraph_words' => 100,
                 'max_description_words' => 300, 'words_per_changed_line' => 4 }.freeze
    # Room for a short summary however small the change is.
    BASE_WORDS = 150
    QUOTED_WORDS = 8
    SHOWN = 3
    ADVICE = 'Split long sentences and paragraphs, move supporting detail into details, ' \
             'and link to the code instead of retelling it.'

    def self.validate!(limits)
      raise Error, 'prose_limits must be a mapping' unless limits.is_a?(Hash) && limits.keys.all?(String)

      unknown = limits.keys - DEFAULTS.keys
      raise Error, "unknown prose_limits key: #{unknown.first}" unless unknown.empty?

      limits.each do |key, value|
        raise Error, "prose_limits.#{key} must be a positive integer" unless value.is_a?(Integer) && value.positive?
      end
    end

    # Reads only the trusted commit, so a candidate checkout's layout cannot change the limits.
    def self.from_ref(root:, ref:)
      return new unless ref

      require_relative 'configuration'
      new(Configuration.trusted(root:, ref:, candidate_commands: false).prose_limits)
    end

    # GitHub may omit the size; the proportional budget is then skipped.
    def self.changed_lines(pull)
      additions, deletions = pull.values_at('additions', 'deletions')
      additions + deletions if additions.is_a?(Integer) && deletions.is_a?(Integer)
    end

    def initialize(limits = {})
      self.class.validate!(limits)
      @limits = DEFAULTS.merge(limits)
    end

    def to_h = @limits.dup

    # Measures GitHub's rendering of body; the pull request supplies the change size.
    def verify_publication!(github, body, kind:, pull:)
      verify!(github.markdown(body), kind:, changed_lines: self.class.changed_lines(pull))
    end

    # html is GitHub's rendering, so Markdown rules come from GitHub rather than a copy of them.
    def verify!(html, kind:, changed_lines:)
      paragraphs = VisibleProse.new(html).paragraphs
      problems = long_sentences(paragraphs) + long_paragraphs(paragraphs) +
                 [length_problem(paragraphs, kind, changed_lines)].compact
      return if problems.empty?

      raise Error, "#{kind.to_s.capitalize} is hard to read: #{summary(problems)}. #{ADVICE}"
    end

    private

    def summary(problems)
      shown = problems.first(SHOWN)
      shown << "#{problems.size - SHOWN} more" if problems.size > SHOWN
      shown.join('; ')
    end

    def long_sentences(paragraphs)
      limit = @limits.fetch('max_sentence_words')
      paragraphs.flatten.filter_map do |sentence|
        count = VisibleProse.words(sentence)
        "a sentence has #{count} words (limit #{limit}): #{quote(sentence)}" if count > limit
      end
    end

    def long_paragraphs(paragraphs)
      limit = @limits.fetch('max_paragraph_words')
      paragraphs.filter_map do |sentences|
        count = VisibleProse.words(sentences.join(' '))
        "a paragraph has #{count} words (limit #{limit}): #{quote(sentences.first)}" if count > limit
      end
    end

    def length_problem(paragraphs, kind, changed_lines)
      limit = budget(kind, changed_lines)
      count = VisibleProse.words(paragraphs.flatten.join(' '))
      return unless limit && count > limit

      scaled = kind == :walkthrough || limit != @limits.fetch('max_description_words')
      scope = scaled ? " for #{changed_lines} changed lines" : ''
      "the visible prose has #{count} words (limit #{limit}#{scope})"
    end

    def budget(kind, changed_lines)
      scaled = BASE_WORDS + (@limits.fetch('words_per_changed_line') * changed_lines) if changed_lines
      return scaled if kind == :walkthrough

      [scaled, @limits.fetch('max_description_words')].compact.min
    end

    def quote(text)
      words = text.split
      "“#{words.first(QUOTED_WORDS).join(' ')}#{'…' if words.size > QUOTED_WORDS}”"
    end
  end
end
