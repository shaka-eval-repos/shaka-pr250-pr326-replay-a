# frozen_string_literal: true

require 'tmpdir'
require_relative 'comments_fixture'

module CommentConfigIntegrationFixture
  include CommentsFixture

  def empty_machine
    Dir.mktmpdir do |dir|
      yield File.join(dir, 'missing.yml')
    end
  end

  def base_blob(contents, new_layout: false)
    object = { '__typename' => 'Blob', 'text' => contents, 'byteSize' => contents.bytesize,
               'isBinary' => false, 'isTruncated' => false }
    fields = new_layout ? { 'object' => nil, 'newObject' => object } : { 'object' => object, 'newObject' => nil }
    response({ 'data' => { 'repository' => fields } })
  end

  def default_base(base = BASE)
    response({ 'data' => { 'repository' =>
             { 'defaultBranchRef' => { 'target' => { 'oid' => base } } } } })
  end

  def pr_pages(trusted)
    [response([trusted]), response([]), response([]), thread_response([])]
  end

  def pr_client(trusted, final_base: default_base, new_blob: nil, new_layout: false, final_new_layout: new_layout)
    responses = [snapshot_response, repository_response('public'), default_base,
                 base_blob("trusted_users: [maintainer]\n", new_layout:), *pr_pages(trusted), snapshot_response,
                 final_base]
    responses << base_blob(new_blob, new_layout: final_new_layout) if new_blob
    client(*responses, repository_response('public'))
  end

  def issue_client(trusted)
    client(response({ 'number' => 42 }), repository_response('public'), default_base,
           base_blob("trusted_users: [maintainer]\n"), response([trusted]),
           default_base, repository_response('public'))
  end

  def assert_base_expression(call)
    assert_equal "#{BASE}:.agents/trusted-github-actors.yml",
                 JSON.parse(call.last).dig('variables', 'expression')
  end

  def assert_trusted_pr(result)
    assert_equal ['Known reviewer'], bodies(result, 'issue_comments')
    assert_equal(['repository'], result['trust_sources'].map { |source| source['scope'] })
    assert_base_expression(@calls[3])
    assert_equal 0, permission_call_count
  end
end

class CommentConfigIntegrationTest < Minitest::Test
  include CommentConfigIntegrationFixture

  def test_public_pr_uses_repo_config_at_default_branch_not_candidate_head
    trusted = comment(id: 80, author: 'maintainer', body: 'Known reviewer')
    empty_machine do |path|
      github = pr_client(trusted)
      result = Shaka::PublicComments::Reader.new(github, machine_path: path).call(expected_head: HEAD)
      assert_trusted_pr(result)
    end
  end

  def test_public_pr_uses_new_allowlist_from_default_branch_not_candidate_head
    trusted = comment(id: 84, author: 'maintainer', body: 'Known reviewer')
    empty_machine do |path|
      reader = Shaka::PublicComments::Reader.new(pr_client(trusted, new_layout: true), machine_path: path)
      result = reader.call(expected_head: HEAD)
      assert_trusted_pr(result)
    end
  end

  def test_public_pr_discards_packet_if_default_branch_config_changes
    trusted = comment(id: 81, author: 'maintainer', body: 'Do not release from stale policy')
    empty_machine do |path|
      github = pr_client(trusted, final_base: default_base('c' * 40), new_blob: "trusted_users: [outsider]\n")
      error = assert_raises(Shaka::Error) do
        Shaka::PublicComments::Reader.new(github, machine_path: path).call(expected_head: HEAD)
      end

      assert_match(/Repository trust config changed/, error.message)
    end
  end

  def test_unrelated_default_branch_move_keeps_same_trust_config
    trusted = comment(id: 83, author: 'maintainer', body: 'Same reviewer')
    empty_machine do |path|
      github = pr_client(trusted, final_base: default_base('c' * 40), new_blob: "trusted_users: [maintainer]\n")
      result = Shaka::PublicComments::Reader.new(github, machine_path: path).call(expected_head: HEAD)

      assert_equal ['Same reviewer'], bodies(result, 'issue_comments')
    end
  end

  def test_allowlist_path_change_invalidates_the_loaded_trust_source
    trusted = comment(id: 85, author: 'maintainer', body: 'Same reviewer')
    empty_machine do |path|
      github = pr_client(trusted, final_base: default_base('c' * 40),
                                  new_blob: "trusted_users: [maintainer]\n", final_new_layout: true)
      error = assert_raises(Shaka::Error) do
        Shaka::PublicComments::Reader.new(github, machine_path: path).call(expected_head: HEAD)
      end
      assert_match(/Repository trust config changed/, error.message)
    end
  end

  def test_public_issue_pins_repo_config_to_default_branch_and_rechecks_it
    trusted = comment(id: 82, author: 'maintainer', body: 'Issue guidance')
    empty_machine do |path|
      github = issue_client(trusted)
      result = Shaka::PublicComments::Reader.new(github, machine_path: path).call(issue_only: true)

      assert_equal ['Issue guidance'], bodies(result, 'issue_comments')
      assert_base_expression(@calls[3])
    end
  end

  def test_machine_config_change_invalidates_loaded_trust
    empty_machine do |path|
      File.write(path, "trusted_users: [maintainer]\n")
      github = client(response({ 'data' => { 'repository' => { 'object' => nil } } }))
      loader = Shaka::PublicComments::TrustConfig.new(github,
                                                      machine_path: path)
      loaded = loader.load(base_oid: BASE)
      File.write(path, "trusted_users: [outsider]\n")

      assert_raises(Shaka::Error) { loader.verify_machine_source(loaded[:sources]) }
    end
  end
end
