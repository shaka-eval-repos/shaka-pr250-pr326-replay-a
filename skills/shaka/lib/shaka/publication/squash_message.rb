# frozen_string_literal: true

require_relative '../error'
require_relative 'publication'
require_relative '../public_comments/bounded_list'

module Shaka
  # The squash commit a PR lands as: `Title (#N)`, a plain-text body wrapped for `git log`,
  # and the co-author trailers the branch commits carried. GitHub copies those trailers only
  # when the squash body is the list of commit messages, so they are carried here instead.
  class SquashMessage
    WIDTH = 72
    COMMIT_PAGES = 3
    TRAILER = /^co-authored-by:[ \t]*(\S[^<\n]*<[^>\n]+>)[ \t]*$/i
    MARKDOWN = [/^\s*```/, /^\s*~~~/, /<details\b/i, /^\s*\|.*\|\s*$/].freeze

    attr_reader :headline, :body

    # GitHub lists at most 250 commits for a PR; a longer PR would lose trailers silently.
    def self.for(github, content)
      commits = PublicComments::BoundedList.new(github, max_pages: COMMIT_PAGES, label: 'Commit listing')
                                           .call("repos/#{github.repository}/pulls/#{github.number}/commits")
      unless commits.length == github.snapshot.dig('commits', 'totalCount')
        raise Error, 'GitHub listed only some of the PR commits, so co-author trailers would be incomplete.'
      end

      new(content, number: github.number, commit_messages: commits.map { |commit| commit.dig('commit', 'message') })
    end

    def initialize(content, number:, commit_messages: [])
      raise Error, 'Squash message content must be a JSON object.' unless content.is_a?(Hash)

      @headline = headline_for(PublicationText.single_line(content['title'], 'squash title'), number)
      @body = [wrap(plain(content['body'])), trailers(commit_messages)].reject(&:empty?).join("\n\n")
    end

    private

    def headline_for(title, number)
      suffix = "(##{number})"
      title.strip.end_with?(suffix) ? title.strip : "#{title.strip} #{suffix}"
    end

    def plain(body)
      text = PublicationText.required(body, 'squash body')
      return text if MARKDOWN.none? { |pattern| text.match?(pattern) }

      raise Error, 'Squash body is plain text for git log: no code fences, tables, or details blocks.'
    end

    # Paragraphs are separated by blank lines. A line that opens with `- ` or `* ` starts a
    # list item, wrapped with a hanging indent. A word longer than the width stays whole.
    def wrap(text)
      text.strip.split(/\n[ \t]*\n/).map { |paragraph| wrap_paragraph(paragraph) }.join("\n\n")
    end

    def wrap_paragraph(paragraph)
      items = paragraph.lines.map(&:strip).reject(&:empty?).slice_before { |line| line.match?(/\A[-*] /) }
      items.map { |item| wrap_words(item.join(' ')) }.join("\n")
    end

    def wrap_words(text)
      indent = text.match?(/\A[-*] /) ? '  ' : ''
      lines = text.split.each_with_object(['']) do |word, wrapped|
        candidate = wrapped.last.empty? ? word : "#{wrapped.last} #{word}"
        if candidate.length <= WIDTH || wrapped.last.strip.empty?
          wrapped[-1] = candidate
        else
          wrapped << "#{indent}#{word}"
        end
      end
      lines.join("\n")
    end

    # Git trailers live in a message's last paragraph; an example earlier in the body is prose.
    def trailers(messages)
      found = messages.compact.flat_map do |message|
        message.to_s.strip.split(/\n[ \t]*\n/).last.to_s.scan(TRAILER).flatten.map(&:strip)
      end
      found.uniq(&:downcase).map { |who| "Co-authored-by: #{who}" }.join("\n")
    end
  end
end
