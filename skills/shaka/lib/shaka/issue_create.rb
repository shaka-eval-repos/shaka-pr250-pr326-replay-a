# frozen_string_literal: true

require 'json'
require 'open3'
require 'optparse'
require_relative 'error'

module Shaka
  # Files already-approved issue text on the fixed public Shaka repository.
  class IssueCreate
    REPOSITORY = 'shakacode/shaka'
    REPOSITORY_ID = 'R_kgDOUZzTGw'
    ISSUE_URL = %r{\Ahttps://github\.com/#{Regexp.escape(REPOSITORY)}/issues/\d+\z}
    USAGE = <<~TEXT
      Usage: shaka issue-create < request

      Read the approved title on the first line and the exact body on the remaining lines.
      A quoted shell heredoc preserves the request as data; one final input newline is removed.
    TEXT

    def self.run(arguments, input: $stdin)
      return help if arguments.one? && %w[--help -h].include?(arguments.first)
      raise OptionParser::InvalidArgument, arguments.join(' ') unless arguments.empty?

      puts create(input.read)
      0
    rescue OptionParser::ParseError, SystemCallError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def self.create(request)
      request.force_encoding(Encoding::UTF_8)
      raise Shaka::Error, 'Issue request must be valid UTF-8 text.' unless request.valid_encoding?

      title, separator, body = request.partition("\n")
      raise Shaka::Error, 'Issue request must contain a title line and a body.' if separator.empty?

      body = body.delete_suffix("\n")
      validate_text(title, body)
      verify_repository!
      create_issue(title, body)
    end

    def self.validate_text(title, body)
      if title.strip.empty? || title.match?(/[\r\0]/) || title != title.strip
        raise Shaka::Error, 'Issue title must be a nonempty line without surrounding whitespace.'
      end
      raise Shaka::Error, 'Issue body must be nonempty valid UTF-8 text.' if body.strip.empty?
      raise Shaka::Error, 'Issue body cannot contain NUL bytes.' if body.include?("\0")
    end

    def self.verify_repository!
      output = gh('repo', 'view', REPOSITORY, '--json', 'id,nameWithOwner,visibility')
      actual = JSON.parse(output)
      expected = { 'id' => REPOSITORY_ID, 'nameWithOwner' => REPOSITORY, 'visibility' => 'PUBLIC' }
      raise Shaka::Error, 'Public Shaka repository identity mismatch; issue was not filed.' unless actual == expected
    rescue JSON::ParserError => e
      raise Shaka::Error, "Cannot read public Shaka repository identity: #{e.message}"
    end

    def self.create_issue(title, body)
      stdout, stderr, status = Open3.capture3(
        { 'GH_HOST' => 'github.com' }, 'gh', 'issue', 'create', '--repo', REPOSITORY,
        '--title', title, '--body-file', '-', stdin_data: body
      )
      require_success!(status, stderr)

      issue_url(stdout)
    end

    def self.require_success!(status, stderr)
      return if status.success?

      detail = stderr.strip
      detail = ": #{detail}" unless detail.empty?
      raise Shaka::Error,
            "GitHub issue creation did not confirm success; inspect live repository state before retrying#{detail}"
    end

    def self.issue_url(stdout)
      url = stdout.lines.map(&:strip).reject(&:empty?).last
      return url if url && ISSUE_URL.match?(url)

      raise Shaka::Error, 'GitHub issue creation returned success without a public Shaka issue URL; ' \
                          'inspect live repository state before retrying.'
    end

    def self.gh(*)
      stdout, stderr, status = Open3.capture3({ 'GH_HOST' => 'github.com' }, 'gh', *)
      raise Shaka::Error, "GitHub repository verification failed: #{stderr.strip}" unless status.success?

      stdout
    end

    def self.help
      puts USAGE
      0
    end

    private_class_method :create, :validate_text, :verify_repository!, :create_issue, :require_success!,
                         :issue_url, :gh, :help
  end
end
