# frozen_string_literal: true

require_relative 'error'

module Shaka
  # Renders description sections, including the decisions list that owns one heading.
  class PublicationSections
    DECISIONS_HEADING = 'Decisions for the maintainer'
    MARKER = '<!-- shaka:decisions -->'

    def self.render(content)
      listed = PublicationText.list(content['sections'], 'sections')
      refuse_heading(listed)
      [*decisions(content['decisions']), *listed.map { |section| section_block(section) }]
    end

    def self.decisions(items)
      listed = PublicationText.list(items, 'decisions')
      return [] if listed.empty?

      lines = listed.map { |item| "- #{PublicationText.single_line(item, 'decision')}" }
      ["#{MARKER}\n## #{DECISIONS_HEADING}\n\n#{lines.join("\n")}"]
    end

    def self.refuse_heading(sections)
      return unless sections.any? { |section| decisions_heading?(section) }

      raise Error, 'Publication Decisions for the maintainer must be supplied as the decisions list, not a section.'
    end

    def self.decisions_heading?(section)
      section.is_a?(Hash) && section['heading'].to_s.strip.casecmp?(DECISIONS_HEADING)
    end

    def self.section_block(section)
      heading = PublicationText.single_line(section['heading'], 'section heading')
      "## #{heading}\n\n#{PublicationText.required(section['body'], "section #{heading}")}"
    end

    private_class_method :decisions, :refuse_heading, :decisions_heading?, :section_block
  end
end
