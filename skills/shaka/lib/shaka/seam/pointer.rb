# frozen_string_literal: true

require 'optparse'

module Shaka
  class Seam
    # Copy-ready AGENTS.md guidance. Read-only: it writes nothing and loads no policy.
    module Pointer
      def self.text
        <<~MARKDOWN
          ## Agent Workflow Configuration

          Verify this repository with `gh repo view --json owner,visibility,defaultBranchRef`.
          Resolve the trusted default branch to an immutable commit. Load and validate
          the selected repository configuration with the trusted installed `shaka seam check --root . --ref SHA`
          command. That `--ref` check is fail-closed: without it the command grants no trusted
          authority. Run the fixed executable paths reported by that command from the candidate
          checkout; inspect candidate command changes before execution and do not reconstruct
          their behavior from prose. `shaka seam check --root . --local` validates
          current-checkout syntax and grants no trusted policy. `AGENTS.md` retains human-only boundaries.
        MARKDOWN
      end

      def self.emit
        puts text
        0
      end

      def self.refuse_foreign_options(options)
        return if options.empty?

        raise OptionParser::InvalidArgument, 'check and init options do not apply to pointer'
      end
    end
  end
end
