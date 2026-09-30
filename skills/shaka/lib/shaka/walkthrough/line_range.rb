# frozen_string_literal: true

require_relative '../error'

module Shaka
  module Walkthrough
    # Finds the 1-based line range a code link names, by text rather than number.
    module LineRange
      CLOSER = %r{\A(?:end|\})[\s;),]*(?:(?:#|//).*)?\z}

      module_function

      def find(lines, from, to: nil, block: false)
        start = unique_line(lines, from)
        finish = if block then block_end(lines, start)
                 elsif to then later_line(lines, start, to)
                 else start
                 end
        [start + 1, finish + 1]
      end

      def unique_line(lines, text)
        matches = lines.each_index.select { |index| lines[index].include?(text) }
        return matches.first if matches.size == 1

        raise Error, "#{text.inspect} matches #{matches.size} lines; use unique text."
      end

      def later_line(lines, start, text)
        found = ((start + 1)...lines.size).find { |index| lines[index].include?(text) }
        return found if found

        raise Error, "no line after #{lines[start].strip.inspect} contains #{text.inspect}."
      end

      # A block runs to the first bare `end` or `}` at its first line's indentation, so
      # `rescue`, `else`, and a signature's closing parenthesis stay inside it. Leaving that
      # indentation first means the language has no such closer here, so the link needs `to`.
      def block_end(lines, start)
        depth = indentation(lines[start])
        closing = ((start + 1)...lines.size).find { |index| block_boundary?(lines[index], depth) }
        return closing if closing && indentation(lines[closing]) == depth

        raise Error, "no closing end or } at the indentation of #{lines[start].strip.inspect}; use to text."
      end

      # The first bare closer at the block's indentation, or the first line indented less.
      def block_boundary?(line, depth)
        text = line.strip
        return false if text.empty?

        indent = indentation(line)
        indent < depth || (indent == depth && text.match?(CLOSER))
      end

      def indentation(line) = line[/\A[ \t]*/].size
    end
  end
end
