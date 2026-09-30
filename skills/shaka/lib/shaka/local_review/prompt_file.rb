# frozen_string_literal: true

require 'rbconfig'
require 'tempfile'
require_relative '../configuration'

module Shaka
  # Reads the repository's review instructions from the same trusted commit as its criteria.
  module LocalReviewPromptFile
    private

    def review_instructions
      script = File.expand_path('../../../scripts/shaka.rb', __dir__)
      with_prompt_arguments do |arguments|
        # The same isolation as scripts/shaka: a project's RUBYOPT and gems stay out of Shaka's Ruby.
        capture(RbConfig.ruby, '--disable-gems', '--disable-rubyopt', script, 'review-prompt', '--head', head,
                '--base', @options[:base], '--reviewer', reviewer, '--effort', effort, *arguments)
      end
    end

    # Yields the `review-prompt` arguments that select the instructions for this reviewer.
    def with_prompt_arguments
      text = trusted_prompt_text
      return yield([]) unless text

      Tempfile.create(['shaka-review-instructions-', '.md']) do |file|
        file.write(text)
        file.close
        yield ['--prompt-file', file.path]
      end
    end

    # The reviewer's trusted model and effort apply where the task named none.
    def apply_trusted_settings!
      agent = reviewer_settings(trusted_review || {})
      return unless agent

      schema = RepositoryConfig::ReviewSchema
      { model: [schema::MODEL, :model_name!], effort: [schema::EFFORT, :effort_level!] }
        .each do |option, (key, check)|
          next if @options[option] || !agent.key?(key)

          # This read skips the schema, so a bad value must fail here as setup, not later in the CLI.
          schema.public_send(check, agent[key], "review.local_review_agents #{key}")
          @options[option] = agent[key]
        end
    end

    def trusted_prompt_text
      review = trusted_review
      return unless review

      ref = @options[:criteria_ref]
      path = configured_prompt_path(review)
      access = { executable: git_executable, capture: method(:capture), resolver: method(:bounded_git) }
      path && Configuration.prompt_at_commit(root:, ref:, path:, git_access: access)
    end

    def trusted_review
      return @trusted_review if defined?(@trusted_review)

      ref = @options[:criteria_ref]
      @trusted_review = (trusted_review_settings(ref) if ref && trusted_seam?(ref))
    end

    # Reads only the review section, so the rest of the seam need not be valid for a review to run;
    # `shaka seam check` validates the whole contract.
    def trusted_review_settings(ref)
      Configuration.review_at_commit(root:, ref:, git: git_executable, capture: method(:capture),
                                     probe: method(:bounded_git))
    end

    # A commit without either configuration keeps the default instructions; invalid sources fail closed.
    def trusted_seam?(ref)
      Configuration.contract_at_commit?(root:, ref:, git: method(:bounded_git))
    end

    # Runs the vetted Git under the review timeout, for this module and TrustedPathResolver.
    def bounded_git(*arguments)
      timeout = @options.fetch(:timeout_seconds)
      result = LocalReviewProcess.capture([git_executable, *arguments], stdin_data: nil, chdir: root, timeout:)
      status = result.last
      raise Shaka::Error, "git timed out after #{timeout}s" unless status
      raise Shaka::Error, 'git output drain timed out after 2s' if status.is_a?(LocalReviewProcess::DrainTimeout)

      result
    end

    # A reviewer's own file wins over the repository-wide one.
    def configured_prompt_path(review)
      prompt_file = RepositoryConfig::ReviewSchema::PROMPT_FILE
      agent = reviewer_settings(review)
      owner, path = agent&.key?(prompt_file) ? ["#{reviewer} ", agent[prompt_file]] : ['review.', review[prompt_file]]
      return if path.nil?
      raise Shaka::Error, "review #{prompt_file} must be a repository path" unless path.is_a?(String)

      @prompt_source = "#{owner}#{prompt_file} #{path}"
      path
    end

    def reviewer_settings(review)
      agents = Array(review[RepositoryConfig::ReviewSchema::LOCAL_REVIEW_AGENTS]).grep(Hash)
      agents.find { |entry| entry.values_at(*ReviewerSelection::IDENTITY).join('/').downcase == reviewer }
    end

    # Names the instructions the reviewer received, for the published review summary.
    def prompt_source = @prompt_source || 'Shaka default'
  end
end
