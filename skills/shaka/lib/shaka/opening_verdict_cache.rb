# frozen_string_literal: true

# Stores successful opening verdicts by hash without retaining description text.

require 'digest'
require 'fileutils'

module Shaka
  # Reuses only successful verdicts for the same opening, model, and prompt.
  class OpeningVerdictCache
    def initialize(opening:, model:, prompt:, directory:)
      key = Digest::SHA256.hexdigest([model, prompt, opening].join("\0"))
      @path = File.join(directory, key)
      @directory = directory
      @prompt = prompt
    end

    def read
      status = File.read(@path).strip
      return { 'status' => 'passed' } if status == 'passed'
      if status == 'flagged'
        return { 'status' => 'flagged', 'reason' => 'The unchanged opening was previously flagged.',
                 'prompt' => @prompt }
      end

      nil
    rescue SystemCallError, IOError
      nil
    end

    def write(verdict)
      return unless %w[passed flagged].include?(verdict['status'])

      FileUtils.mkdir_p(@directory, mode: 0o700)
      File.write(@path, verdict.fetch('status'), mode: 'w', perm: 0o600)
    rescue SystemCallError
      nil # A cache failure must not change the advisory result.
    end
  end
end
