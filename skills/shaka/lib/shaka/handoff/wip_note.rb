# frozen_string_literal: true

require_relative '../publication/publishing'
require_relative '../publication/wip_details'

module Shaka
  class Handoff
    # Reads back the WIP Details note that `description` published, from the description's managed region.
    module WipNote
      NOTE = %r{<details>\n<summary>#{WipDetails::SUMMARY}</summary>\n\n(.*?)\n\n</details>}m
      ROW = /\A\| (.+?) \| (.*) \|\z/

      module_function

      # The Revision cell of a complete note, or nil when the body holds none.
      def revision(body)
        # A body saved from GitHub's web editor comes back with CRLF line endings.
        note = managed_region(body.to_s.gsub("\r\n", "\n"))[NOTE, 1] or return
        cell = cells(note)&.fetch(WipDetails::FIELDS.keys.index('revision'))
        cell unless cell.to_s.strip.empty?
      end

      # The Value column in field order, or nil for a partial or reordered table WipDetails did not render.
      def cells(note)
        rows = note.lines.drop(2).map { |line| line.chomp.match(ROW)&.captures || [] }
        rows.map(&:last) if rows.map(&:first) == WipDetails::FIELDS.values
      end

      # Revision reads `BRANCH @ SHA`; only the part after the last ` @ ` is the head, whatever the branch is named.
      def head(revision) = revision.to_s.split(' @ ').last.to_s.strip

      # Only text between one opening and one later closing marker is the helper's own; anyone who can
      # edit the body can write elsewhere in it.
      def managed_region(body)
        open = body.index(Publishing::OPEN_MARK)
        close = body.index(Publishing::CLOSE_MARK)
        single = body.scan(Publishing::OPEN_MARK).one? && body.scan(Publishing::CLOSE_MARK).one?
        return '' unless single && open < close

        body[(open + Publishing::OPEN_MARK.length)...close]
      end
    end
  end
end
