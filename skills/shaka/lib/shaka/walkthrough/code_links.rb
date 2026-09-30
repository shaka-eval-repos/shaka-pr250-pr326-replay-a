# frozen_string_literal: true

require 'uri'
require_relative 'line_range'

module Shaka
  module Walkthrough
    # Turns walkthrough `code:NAME` link targets into commit-pinned line-range permalinks.
    # Each name locates its lines by text in the file at the head, so a range cannot drift
    # onto other code when earlier commits move lines, and text that is missing or matches
    # more than one line refuses publication instead of guessing.
    class CodeLinks
      # Fenced blocks and code spans show Markdown literally, so a link example there stays as
      # written; matching them first leaves only prose references to resolve. Fences inside
      # block quotes or lists are not recognized.
      FENCE = /^[ \t]*(?<fence>(?<mark>[`~])\k<mark>{2,}).*?^[ \t]*\k<fence>\k<mark>*[ \t]*$/m
      SPAN = /(?<ticks>`+).*?(?<!`)\k<ticks>(?!`)/m
      CODE = Regexp.union(FENCE, SPAN)
      REFERENCE = /\]\(code:(?<name>[^)\s]*)\)/
      TOKEN = Regexp.union(CODE, REFERENCE)

      # Rewrites the rendered walkthrough, so links in the summary, sections, table, and
      # details all resolve the same way.
      def self.resolve(body, content, github)
        return body unless content.key?('code_links')

        new(content.fetch('code_links'), github, content.fetch('head')).rewrite(body)
      end

      def initialize(links, github, head)
        raise Error, 'Walkthrough code_links must be an object.' unless links.is_a?(Hash)

        @links = links
        @github = github
        @head = head
        @files = {}
        @listings = {}
        @urls = {}
      end

      def rewrite(body)
        body.gsub(TOKEN) do
          name = Regexp.last_match[:name]
          name ? "](#{url(name)})" : Regexp.last_match[0]
        end
      end

      private

      def url(name)
        @urls[name] ||= begin
          link = @links[name]
          raise Error, "Walkthrough references undefined code link #{name}." unless link

          first, last = range(name, link)
          anchor = first == last ? "#L#{first}" : "#L#{first}-L#{last}"
          "https://github.com/#{@github.repository}/blob/#{@head}/#{encoded(link['path'])}#{anchor}"
        end
      end

      def range(name, link)
        path, from = definition(name, link)
        LineRange.find(file(name, path), from, to: link['to'], block: link['block'])
      rescue Error => e
        raise e if e.message.start_with?('Walkthrough code link')

        raise Error, "Walkthrough code link #{name}: #{e.message}"
      end

      def definition(name, link)
        raise Error, "Walkthrough code link #{name} must be an object." unless link.is_a?(Hash)
        raise Error, "Walkthrough code link #{name} needs a repository-relative path." unless relative?(link['path'])
        raise Error, "Walkthrough code link #{name} needs from text." unless text?(link['from'])

        check_end(name, link)
        [link['path'], link['from']]
      end

      def check_end(name, link)
        block = link['block']
        raise Error, "Walkthrough code link #{name} has a non-boolean block." unless [nil, true, false].include?(block)
        raise Error, "Walkthrough code link #{name} takes either to or block, not both." if link['block'] && link['to']
        raise Error, "Walkthrough code link #{name} has invalid to text." if link.key?('to') && !text?(link['to'])
      end

      def relative?(path)
        path.is_a?(String) && !path.start_with?('/') && !path.split('/', -1).intersect?(['', '.', '..'])
      end

      def text?(value) = value.is_a?(String) && !value.strip.empty?

      def file(name, path)
        @files[path] ||= begin
          regular_file!(path)
          decoded(path, @github.api("repos/#{@github.repository}/contents/#{encoded(path)}?ref=#{@head}"))
        end
      rescue Error => e
        raise Error, "Walkthrough code link #{name}: #{e.message}"
      end

      def decoded(path, response)
        unless response['type'] == 'file' && response['encoding'] == 'base64'
          raise Error, "#{path} is not a regular file under 1 MB at #{@head}."
        end

        text = response['content'].to_s.unpack1('m').force_encoding(Encoding::UTF_8)
        raise Error, "#{path} is not valid UTF-8 at #{@head}." unless text.valid_encoding?

        text.split("\n", -1)
      end

      # The contents API follows a symlink to its target's text, while the permalink would
      # show the link itself, so only an entry the directory lists as a file qualifies.
      def regular_file!(path)
        directory = File.dirname(path)
        suffix = directory == '.' ? '' : "/#{encoded(directory)}"
        @listings[directory] ||= @github.api_list("repos/#{@github.repository}/contents#{suffix}?ref=#{@head}")
        entry = @listings[directory].find { |item| item['name'] == File.basename(path) }
        raise Error, "#{path} is not a regular file at #{@head}." unless entry && entry['type'] == 'file'
      end

      def encoded(path) = path.split('/').map { |segment| URI.encode_uri_component(segment) }.join('/')
    end
  end
end
