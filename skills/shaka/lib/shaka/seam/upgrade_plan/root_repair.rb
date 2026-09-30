# frozen_string_literal: true

module Shaka
  class Seam
    class UpgradePlan
      # Conservative root calculation repairs for known wrapper patterns.
      module RootRepair
        private

        def repair_root(text)
          if text.include?(OLD_ROOT)
            return [nil, nil] unless exits_on_error?(text)

            return [text.sub(OLD_ROOT, GIT_ROOT), 'recognized shell root discovery']
          end
          return custom_shell_root(text) if text.match?(shell_root_pattern) && exits_on_error?(text)
          return custom_ruby_root(text) if text.match?(ruby_root_pattern)
          return [nil, nil] if ambiguous_root?(text)

          [text, nil]
        end

        def exits_on_error?(text)
          before_root = text.lines.take_while { |line| !line.match?(/^\s*root\s*=/) }
          before_root.reduce(false) do |enabled, line|
            next true if line.match?(/^\s*set\s+-(?:[a-zA-Z]*e[a-zA-Z]*|o\s+errexit)(?:\s|$)/)
            next false if line.match?(/^\s*set\s+\+(?:[a-zA-Z]*e[a-zA-Z]*|o\s+errexit)(?:\s|$)/)

            enabled
          end
        end

        def custom_shell_root(text)
          result = text.sub(shell_root_pattern) do
            "#{::Regexp.last_match(1)}#{GIT_ROOT.delete_prefix('root=')}#{::Regexp.last_match(2)}"
          end
          [result, 'custom shell root discovery']
        end

        def custom_ruby_root(text)
          result = text.sub(ruby_root_pattern) do
            match = ::Regexp.last_match
            expression = match[:expression].start_with?('Pathname') ? "Pathname(#{RUBY_GIT_ROOT})" : RUBY_GIT_ROOT
            indent = match[:indent]
            assignment = "#{indent}root = #{expression}"
            failure = "#{indent}abort 'Cannot find repository root' unless $?.success? && !root.to_s.empty?"
            "#{assignment}\n#{failure}"
          end
          [result, 'custom Ruby root discovery']
        end

        def shell_root_pattern = %r{^(\s*root=)\$\(dirname (?:--? )?"\$0"\)/\.\./\.\.(\s*)$}

        def ruby_root_pattern
          file = "File\\.expand_path\\(['\"]\\.\\./\\.\\.['\"], __dir__\\)"
          pathname = 'Pathname\\(__dir__\\)\\.parent\\.parent'
          /^(?<indent>[ \t]*)root = (?<expression>#{file}|#{pathname})[ \t]*$/
        end

        def ambiguous_root?(text)
          text.include?('../..') || text.include?('Pathname(__dir__).parent.parent')
        end

        def invocation_relative?(text)
          remaining = text.gsub(GIT_ROOT, '').gsub(RUBY_GIT_ROOT, '')
          shell = /\$(?:0\b|\{0[^}]*\})|\bBASH_SOURCE\b/
          ruby = /\b__dir__\b|\b__FILE__\b|\b__file__\b|\brequire_relative\b|\$PROGRAM_NAME\b/
          remaining.match?(shell) || remaining.match?(ruby)
        end
      end
    end
  end
end
