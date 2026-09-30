# frozen_string_literal: true

require_relative 'attention'
require_relative 'error'
require_relative 'publication_sections'

module Shaka
  # Keeps awaiting-answer aligned with the description's decisions list.
  class DecisionLabels
    # A closed fence hides the marker. An unclosed opener does not, so a broken
    # fence in an earlier section cannot drop a published question.
    # The opener is atomic, so it cannot shrink to let a later shorter fence close it.
    FENCE = /^[ \t]*(?<fence>(?>(?<mark>[`~])\k<mark>{2,}))[^\n]*\n.*?^[ \t]*\k<fence>\k<mark>*[ \t]*$/m

    def self.guard(github, content, existing_body = nil)
      decisions = list(content)
      if decisions.nil? && asks_for_decisions?(existing_body)
        raise Error, 'Pass decisions or an empty list; the pull request already asks for decisions.'
      end
      return if decisions.nil? || decisions.empty?
      raise Error, 'Pull request is not open.' unless github.snapshot['state'] == 'OPEN'

      Attention.new(github).refuse_merge_wait
    end

    def self.sync(github, content)
      decisions = list(content)
      return if decisions.nil?

      attention = Attention.new(github)
      decisions.empty? ? attention.release_answer : attention.call(state: 'answer', refuse_merge: true)
    end

    def self.asks_for_decisions?(body)
      body.to_s.gsub(FENCE, '').each_line.any? { |line| line.strip == PublicationSections::MARKER }
    end

    def self.list(content)
      return unless content.key?('decisions')

      decisions = content['decisions']
      raise Error, 'Publication decisions must be a list.' unless decisions.is_a?(Array)

      decisions
    end

    private_class_method :asks_for_decisions?, :list
  end
end
