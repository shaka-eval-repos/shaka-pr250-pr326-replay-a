# frozen_string_literal: true

# A non-skill consumer of the installed gem. It supplies its own GitHub adapter
# instead of Shaka's gh-based client and prints the screened packet as JSON.
require 'json'
require 'shaka/public_comments'

# Answers only the reads the reader needs for one public issue.
class RecordedGitHub
  attr_reader :repository, :number

  def initialize
    @repository = 'example/library'
    @number = 7
  end

  def api(path, **)
    case path
    when 'repos/example/library' then { 'visibility' => 'public' }
    when 'repos/example/library/issues/7' then { 'number' => 7 }
    when %r{/collaborators/([A-Za-z0-9-]+)/permission\z}
      { 'user' => { 'login' => Regexp.last_match(1) },
        'permission' => Regexp.last_match(1) == 'maintainer' ? 'write' : 'read' }
    else raise Shaka::Error.new("Unexpected read: #{path}", http_status: 404)
    end
  end

  def api_list(path)
    raise Shaka::Error, "Unexpected list: #{path}" unless path.start_with?('repos/example/library/issues/7/comments?')

    [comment(1, 'maintainer', 'User'), comment(2, 'stranger', 'User'), comment(3, 'helper[bot]', 'Bot')]
  end

  def graphql(query, _variables = {})
    return { 'repository' => { 'defaultBranchRef' => { 'target' => { 'oid' => 'a' * 40 } } } } if
      query.include?('defaultBranchRef')

    { 'repository' => { 'object' => nil } }
  end

  private

  def comment(id, login, type)
    { 'id' => id, 'user' => { 'login' => login, 'type' => type }, 'body' => "comment #{id}",
      'html_url' => "https://github.com/example/library/issues/7#issuecomment-#{id}" }
  end
end

reader = Shaka::PublicComments::Reader.new(RecordedGitHub.new, machine_path: ARGV.fetch(0))
loaded = $LOADED_FEATURES.grep(%r{/gems/shaka-.+/})
puts JSON.generate(reader.call(issue_only: true).merge('loaded_from' => loaded))
