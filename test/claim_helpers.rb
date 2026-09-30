# frozen_string_literal: true

require 'json'
require 'stringio'
require 'shaka/claim'

# Runs `Shaka::Claim` against canned `gh pr list` and `git ls-remote` output.
module ClaimHelpers
  STATUS = Struct.new(:exitstatus)

  private

  def claim(query, prs:, branches:, branch_name: nil, tracker_branch: nil)
    Shaka::Claim.new(query: query, root: Dir.pwd, runner: runner(prs: prs, branches: branches),
                     branch_name: branch_name, tracker_branch: tracker_branch).result
  end

  def capture_cli(arguments, prs:, branches:)
    stdout = StringIO.new
    original = $stdout
    $stdout = stdout
    status = Shaka::Claim.run(arguments, runner: runner(prs: prs, branches: branches))
    [stdout.string, status]
  ensure
    $stdout = original
  end

  def runner(prs:, branches:)
    lambda do |argv, **|
      return [JSON.generate(prs), '', STATUS.new(0)] if argv[1] == 'pr'
      return [branches, '', STATUS.new(0)] if argv[1] == 'ls-remote'

      raise "Unexpected command: #{argv.inspect}"
    end
  end
end
