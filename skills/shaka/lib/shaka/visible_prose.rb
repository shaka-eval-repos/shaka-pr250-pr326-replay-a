# frozen_string_literal: true

# Reduces GitHub's rendered HTML to the prose a reader sees without expanding anything.

require 'cgi'

module Shaka
  # Splits rendered HTML into paragraphs and list items, each as its sentences.
  class VisibleProse
    # Content inside these is hidden, except in an open details block and a collapsed block's summary.
    CONTAINER = %r{\A<(/?)(details|summary|pre|table|h[1-6]|blockquote)\b([^>]*)>}i
    BLOCK = %r{\A</?(?:p|li|ul|ol|div|hr)\b}i
    ITEM = %r{\A<(/?)li\b}i
    PARAGRAPH = %r{\A</?p\b}i
    CODE = %r{\A<(/?)code\b}i
    BREAK = /\A<br\b/i
    # A false split only shortens a sentence, so anything may start the next one, as in "iOS" or an emoji.
    # An ellipsis may end a sentence too.
    SENTENCE_END = /(?<=[.!?…])["'”’)\]]*\s+/

    def self.words(text) = text.split(/[[:space:]]+/).count { |token| token.match?(/[[:alnum:]]/) }

    def initialize(html)
      @stack = []
      @items = 0
      @summary = false
      @code = false
      @text = html.to_s.split(/(<[^>]*>)/).map { |token| token.start_with?('<') ? tag(token) : text(token) }.join
    end

    def paragraphs
      @text.split("\n\n").map { |block| block.gsub(/[[:space:]]+/, ' ').strip.split(SENTENCE_END) }.reject(&:empty?)
    end

    private

    def visible? = @summary || @stack.all?(:shown)

    def text(token)
      @code_tail = token if @code
      visible? && !@code ? CGI.unescapeHTML(token.gsub('&nbsp;', ' ')).gsub(/[[:space:]]+/, ' ') : ''
    end

    # A hard line break separates words; other inline tags join the text around them.
    def tag(token)
      match = token.match(CONTAINER)
      return container(*match.captures) if match
      return code(token.match(CODE)[1].empty?) if token.match?(CODE)

      boundary(token)
    end

    # A list item is measured whole, even when it holds several paragraphs.
    def boundary(token)
      @items = [@items + (token.match(ITEM)[1].empty? ? 1 : -1), 0].max if token.match?(ITEM)
      return ' ' if @items.positive? && token.match?(PARAGRAPH)

      return "\n\n" if token.match?(BLOCK)

      token.match?(BREAK) ? ' ' : ''
    end

    def container(closing, name, attributes)
      if name.casecmp?('summary')
        @summary = closing.empty? && @stack.last == :collapsed && @stack[0...-1].all?(:shown)
      elsif closing.empty?
        @stack.push(state(name, attributes))
      else
        @stack.pop
      end
      "\n\n"
    end

    def state(name, attributes)
      return :hidden unless name.casecmp?('details')

      attributes.match?(/\bopen\b/i) ? :shown : :collapsed
    end

    # An inline code span reads as one capitalized word, so a sentence may still start with one.
    # It keeps a final `.`, `!`, `?`, or `…`, which may end the sentence, as in `empty?`.
    def code(opening)
      @code = opening
      @code_tail = '' if opening
      return '' unless visible?

      opening ? ' Code' : "#{@code_tail.to_s.strip[/[.!?…]\z/]} "
    end
  end
end
