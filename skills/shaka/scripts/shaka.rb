# frozen_string_literal: true

require_relative '../lib/shaka/ruby_requirement'

require 'json'
require 'optparse'
require_relative '../lib/shaka/github'
require_relative '../lib/shaka/attention'
require_relative '../lib/shaka/pr_watch/command'
require_relative '../lib/shaka/handoff'
require_relative '../lib/shaka/issue_create'
require_relative '../lib/shaka/public_comments'
require_relative '../lib/shaka/checkpoint'
require_relative '../lib/shaka/claim'
require_relative '../lib/shaka/decision_labels'
require_relative '../lib/shaka/publication/deployment_link'
require_relative '../lib/shaka/doctor'
require_relative '../lib/shaka/evidence/command'
require_relative '../lib/shaka/enforcement'
require_relative '../lib/shaka/merge'
require_relative '../lib/shaka/merge_limits'
require_relative '../lib/shaka/opening_publication'
require_relative '../lib/shaka/publication/squash_message'
require_relative '../lib/shaka/prefix'
require_relative '../lib/shaka/publication/publication'
require_relative '../lib/shaka/review_reply'
require_relative '../lib/shaka/recommendation'
require_relative '../lib/shaka/repos'
require_relative '../lib/shaka/review_prompt'
require_relative '../lib/shaka/local_review'
require_relative '../lib/shaka/reviewer'
require_relative '../lib/shaka/seam'
require_relative '../lib/shaka/status'
require_relative '../lib/shaka/trusted_config_source'
require_relative '../lib/shaka/usage/usage'
require_relative '../lib/shaka/walkthrough/code_links'
require_relative '../lib/shaka/work'
require_relative '../lib/shaka/workflow'
require_relative '../lib/shaka/workflow_version'

if ARGV.first == 'usage'
  ARGV.shift
  exit Shaka::Usage.run(ARGV)
end

if ARGV.first == 'pr' && ARGV[1] == 'watch'
  ARGV.shift(2)
  exit Shaka::PrWatch::Command.run(ARGV)
end

if ARGV.first == 'issue-create'
  ARGV.shift
  exit Shaka::IssueCreate.run(ARGV)
end

if ARGV.first == 'work'
  ARGV.shift
  exit Shaka::Work.run(ARGV)
end

if ARGV.first == 'recommendation'
  ARGV.shift
  exit Shaka::Recommendation.run(ARGV)
end

if ARGV.first == 'checkpoint'
  ARGV.shift
  exit Shaka::Checkpoint.run(ARGV)
end

if ARGV.first == 'review-prompt'
  ARGV.shift
  exit Shaka::ReviewPrompt.run(ARGV)
end

if ARGV.first == 'review'
  ARGV.shift
  exit Shaka::LocalReview.run(ARGV)
end

if ARGV.first == 'reviewer'
  ARGV.shift
  exit Shaka::Reviewer.run(ARGV)
end

if ARGV.first == 'seam'
  ARGV.shift
  exit Shaka::Seam.run(ARGV)
end

if ARGV.first == 'workflow'
  ARGV.shift
  exit Shaka::Workflow.run(ARGV)
end

if ARGV.first == 'enforcement'
  ARGV.shift
  exit Shaka::Enforcement.run(ARGV)
end

if ARGV.first == 'doctor'
  ARGV.shift
  exit Shaka::Doctor.run(ARGV)
end

if ARGV.first == 'evidence'
  ARGV.shift
  exit Shaka::Evidence::Command.run(ARGV)
end

if ARGV.first == 'claim'
  ARGV.shift
  exit Shaka::Claim.run(ARGV)
end

if ARGV.first == 'repos'
  ARGV.shift
  exit Shaka::Repos.run(ARGV)
end

if ARGV.first == 'prefix'
  ARGV.shift
  exit Shaka::Prefix.run(ARGV)
end

COMMANDS = %w[pr comments description reply resolve walkthrough merge attention squash-message handoff].freeze

def content(path)
  parsed = JSON.parse(File.read(path, encoding: 'UTF-8'))
  raise Shaka::Error, 'Content file must hold a JSON object.' unless parsed.is_a?(Hash)

  parsed
rescue JSON::ParserError => e
  raise Shaka::Error, "Content file is not valid JSON: #{e.message}"
end

def merge_limits(options)
  Shaka::MergeLimits.from_ref(root: options[:root] || Dir.pwd, ref: options[:ref],
                              confirmed_head: options[:confirmed_head])
end

def require_merge_ref!(options)
  return if options[:ref].is_a?(String) && !options[:ref].strip.empty?

  raise Shaka::Error, 'merge requires --ref so policy comes from a trusted commit'
end

# Reads trusted limits through the opening check's guarded Git; an unreadable trusted commit is reported.
def description_prose_limits(root, ref)
  return [Shaka::ProseLimits.new, {}] unless ref

  limits = Shaka::OpeningPublication.with_safe_path(root:, select_gh: false) do |candidate_root|
    Shaka::ProseLimits.from_ref(root: candidate_root, ref:)
  end
  [limits, {}]
rescue Shaka::Error => e
  [Shaka::ProseLimits.new, { 'prose_limits' => "Default prose limits apply: #{e.message}" }]
end

# The Git a description may run to read the helper's own commit, or nil when PATH offers
# only one that could load candidate code; the workflow version then shows no commit.
def vetted_git(candidate_root)
  Shaka::LocalReviewPathGuard.safe_executable(ENV.fetch('PATH'), 'git', candidate_root)
rescue Shaka::Error, SystemCallError
  nil
end

def walkthrough_body(options, github)
  return File.read(options.fetch(:body_file), encoding: 'UTF-8') if options[:body_file]

  walkthrough = content(options.fetch(:content_file)).merge('head' => options.fetch(:head))
  Shaka::Walkthrough::CodeLinks.resolve(Shaka::Publication.walkthrough(walkthrough), walkthrough, github)
end

def usage_banner
  ["Usage: shaka (#{COMMANDS.join('|')}) OWNER/REPO NUMBER [options]; ",
   'shaka usage --help; shaka work --help; shaka recommendation --help; shaka checkpoint --help',
   '; shaka reviewer --help', '; shaka review-prompt --help', '; shaka review run --help',
   '; shaka review check --help', '; shaka review publish --help', '; shaka seam check --help',
   '; shaka workflow --help', '; shaka enforcement --help', '; shaka doctor --help',
   '; shaka repos --help; shaka prefix --help; shaka issue-create --help'].join
end

def merge_flags(flags, options)
  flags.on('--review-waiver REASON', 'Merge without review evidence') { |value| options[:review_waiver] = value }
  flags.on('--limits-confirmed-head SHA', 'Head confirmed past limits') { |sha| options[:confirmed_head] = sha }
  flags.on('--squash-message PATH', 'Squash commit title and body as JSON') { |path| options[:squash_message] = path }
  flags.on('--woken-by WHAT', 'For handoff: what will wake this session') { |value| options[:woken_by] = value }
end

def opening_flags(flags, options)
  flags.on('--opening-reviewer ID', 'Configured provider/family for an opening check') do |value|
    options[:opening_reviewer] = value
  end
  flags.on('--opening-model MODEL', 'Model for the opening reviewer') { |value| options[:opening_model] = value }
end

def trust_flags(flags, options)
  flags.on('--root DIR', 'Repository root for trusted seam settings') { |value| options[:root] = value }
  flags.on('--ref REF', 'Trusted commit for seam settings') { |value| options[:ref] = value }
end

options = {}
parser = OptionParser.new do |flags|
  flags.banner = usage_banner
  flags.on('--head SHA', 'Expected current PR head') { |value| options[:head] = value }
  flags.on('--content-file PATH', 'Publication content as JSON') { |value| options[:content_file] = value }
  flags.on('--body-file PATH', 'Walkthrough Markdown file') { |value| options[:body_file] = value }
  flags.on('--key NAME', 'Stable reply key; reused instead of duplicating') { |value| options[:key] = value }
  flags.on('--comment ID', Integer, 'Root review comment for an inline-thread reply') do |value|
    options[:comment] = value
  end
  flags.on('--thread ID', 'Inline review thread to mark resolved') { |value| options[:thread] = value }
  flags.on('--walkthrough ID', 'Published COMMENT review ID') { |value| options[:walkthrough] = value }
  flags.on('--ci-review-wait MODE', Shaka::CiReviewWait::VALUES, 'CI reviews to await: none, one, all') do |value|
    options[:ci_review_wait] = value
  end
  merge_flags(flags, options)
  trust_flags(flags, options)
  opening_flags(flags, options)
  flags.on('--base BRANCH', 'Base branch the change was validated against') { |value| options[:base] = value }
  flags.on('--issue', 'Read issue comments instead of PR comments') { options[:issue_only] = true }
  flags.on('--state STATE', Shaka::Attention::STATES, 'Decision the PR awaits: answer, merge, resume, none') do |value|
    options[:state] = value
  end
  flags.on('-h', '--help', 'Show usage') do
    puts flags
    exit
  end
end

begin
  parser.parse!(ARGV)
  command, repository, number = ARGV
  raise OptionParser::InvalidArgument, parser.to_s unless ARGV.length == 3 && COMMANDS.include?(command)
  raise OptionParser::InvalidArgument, '--issue is only for comments' if options[:issue_only] && command != 'comments'
  if options[:review_waiver] && command != 'merge'
    raise OptionParser::InvalidArgument, '--review-waiver is only for merge'
  end
  if options[:squash_message] && command != 'merge'
    raise OptionParser::InvalidArgument, '--squash-message is only for merge'
  end
  raise Shaka::Error, '--thread is only for resolve.' if options[:thread] && command != 'resolve'
  raise Shaka::Error, '--woken-by is only for handoff.' if options[:woken_by] && command != 'handoff'
  if command == 'handoff' && options[:ref].to_s.strip.empty?
    raise Shaka::Error, 'handoff requires --ref so seam-required checks come from a trusted commit.'
  end
  raise Shaka::Error, 'resolve requires --thread THREAD_ID.' if command == 'resolve' && options[:thread].to_s.empty?
  if options[:opening_reviewer] && command != 'description'
    raise Shaka::Error, '--opening-reviewer is only for description.'
  end
  if options[:opening_model] && !options[:opening_reviewer]
    raise Shaka::Error, '--opening-model requires --opening-reviewer.'
  end

  if options[:opening_model] && options[:opening_reviewer]
    reviewer = Shaka::ReviewerSelection.parse(options[:opening_reviewer]).values.map(&:downcase).join('/')
    raise Shaka::Error, '--opening-model is unsupported for openai/codex.' if reviewer == 'openai/codex'
  end

  github = Shaka::GitHub.new(repository, number)
  if %w[pr walkthrough merge handoff].include?(command)
    seam = Shaka::TrustedConfigSource.from_ref(root: options[:root] || Dir.pwd, ref: options[:ref])
  end
  seam_required_checks = seam&.merge&.fetch('required_checks', nil)
  result = case command
           when 'pr' then Shaka::Status.new(github, seam_required_checks:).call
           when 'comments'
             issue_only = options.fetch(:issue_only, false)
             raise OptionParser::InvalidArgument, '--head does not apply to issues' if issue_only && options[:head]

             Shaka::PublicComments::Reader.new(github).call(issue_only:,
                                                            expected_head: issue_only ? nil : options[:head])
           when 'description'
             root = options[:root] || Dir.pwd
             prose, prose_note = description_prose_limits(root, options[:ref])
             Shaka::OpeningPublication.with_safe_path(root:) do |candidate_root, gh, neutral|
               raise Shaka::Error, 'GitHub CLI is unavailable; install gh and authenticate.' unless gh

               workflow_version = Shaka::WorkflowVersion.current(git: vetted_git(candidate_root))

               github = Shaka::GitHub.new(repository, number, runner: lambda do |argv, stdin_data:|
                 Open3.capture3(gh, *argv.drop(1), stdin_data:, chdir: neutral)
               end)
               described = Shaka::DeploymentLink.resolve(content(options.fetch(:content_file)), github)
               usage_records = nil
               carried = nil
               published = github.description(prose:) do |pull|
                 carried, usage_records = Shaka::UsageRecords.carry_from(described, pull)
                 rendered = Shaka::Publication.description(carried, workflow_version, pull)
                 Shaka::DecisionLabels.guard(github, carried, pull['body'])
                 rendered
               end
               attention = Shaka::DecisionLabels.sync(github, carried)
               opening = Shaka::OpeningPublication.new(root:, ref: options[:ref],
                                                       reviewer: options[:opening_reviewer],
                                                       model: options[:opening_model]).call(described['summary'])
               published.merge('opening' => opening, 'usage_records' => usage_records).merge(prose_note).tap do |result|
                 result['attention'] = attention if attention
               end
             end
           when 'reply'
             # A review lookup contacts GitHub, so a missing key fails before that lookup.
             key = options.fetch(:key)
             github.reply(body: Shaka::ReviewReply.compose(content(options.fetch(:content_file)), github),
                          key: key, comment: options[:comment])
           when 'resolve'
             github.resolve_thread(options.fetch(:thread))
           when 'walkthrough'
             github.walkthrough(head: options.fetch(:head), body: walkthrough_body(options, github),
                                seam_required_checks:, prose: Shaka::ProseLimits.new(seam&.prose_limits || {}))
           when 'merge'
             head = options.fetch(:head)
             require_merge_ref!(options)
             review = { required: seam&.review&.fetch('required'), waiver: options[:review_waiver],
                        root: options[:root] || Dir.pwd }
             squash_message = options[:squash_message] &&
                              Shaka::SquashMessage.for(github, content(options[:squash_message]))
             Shaka::Merge.new(github, ci_review_wait: options[:ci_review_wait],
                                      seam_wait: seam&.review&.fetch('ci_review_wait'), review:,
                                      seam_required_checks:).call(
                                        head:,
                                        base: options.fetch(:base),
                                        walkthrough: options.fetch(:walkthrough),
                                        limits: merge_limits(options), squash_message:
                                      )
           when 'attention' then Shaka::Attention.new(github).call(state: options.fetch(:state))
           when 'squash-message'
             message = Shaka::SquashMessage.for(github, content(options.fetch(:content_file)))
             github.squash_comment(head: options.fetch(:head), message:)
           when 'handoff' then Shaka::Handoff.new(github, seam_required_checks:).call(head: options[:head],
                                                                                      woken_by: options[:woken_by])
           end
  puts JSON.pretty_generate(result)
  exit Shaka::Handoff.exit_status(result) if command == 'handoff'
rescue OptionParser::ParseError, KeyError, SystemCallError, Shaka::Error => e
  warn "shaka: #{e.message}"
  exit 1
end
