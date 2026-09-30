# frozen_string_literal: true

module Shaka
  # Loads only review criteria present at the separately verified trusted commit.
  module LocalReviewCriteria
    private

    def trusted_criteria(marker)
      ref = @options[:criteria_ref]
      return '' unless ref

      paths = applicable_criteria(ref)
      @criteria_supplied = paths.any?
      paths.map do |path|
        source = capture(git_executable, '-C', root, 'show', "#{ref}:#{path}")
        label = "TRUSTED CRITERIA #{marker}"
        "--- BEGIN #{label} FROM #{ref}:#{path} ---\n#{source}\n--- END #{label} ---\n\n"
      end.join
    end

    def applicable_criteria(ref)
      paths = capture(git_executable, '-C', root, 'diff', '--no-renames', '--name-only', '-z',
                      "#{@options[:base]}...#{head}", '--').split("\0")
      files = capture(git_executable, '-C', root, 'ls-tree', '-r', '--name-only', '-z', ref, '--').split("\0")
      files.select { |file| applicable_agents_file?(file, paths) }.sort_by { |file| [file.count('/'), file] }
    end

    def applicable_agents_file?(file, changed_paths)
      return true if file == 'AGENTS.md'
      return false unless file.end_with?('/AGENTS.md')

      directory = File.dirname(file)
      changed_paths.any? { |path| path.start_with?("#{directory}/") }
    end
  end
end
