# frozen_string_literal: true

require_relative 'test_helper'
require 'json'
require 'shaka/walkthrough/code_links'

module CodeLinksFixtures
  HEAD = 'a' * 40
  BLOB = "https://github.com/owner/repo/blob/#{HEAD}".freeze
  PACKAGE = <<~RUBY
    class Package
      def prepare(root)
        stage(root)
      end

      def stage(root)
        copy(root)
        publish(root)
      end

      def publish(root)
        rename(root)
      end
    end
  RUBY
  SCRIPT = <<~PYTHON
    def first():
        return 1

    def second():
        return 2
  PYTHON

  FakeGitHub = Struct.new(:files, :requests, :symlinks) do
    def repository = 'owner/repo'

    def api(path, **)
      requests << path
      name = path[%r{/contents/(.+)\?ref=}, 1]
      raise Shaka::Error, "gh api #{path} failed (exit 1)." unless files.key?(name)

      { 'type' => 'file', 'encoding' => 'base64', 'content' => [files.fetch(name)].pack('m') }
    end

    def api_list(path)
      requests << path
      directory = path[%r{/contents/?(.*)\?ref=}, 1]
      (files.keys | symlinks).select { |name| File.dirname(name) == directory }.map do |name|
        { 'name' => File.basename(name), 'type' => symlinks.include?(name) ? 'symlink' : 'file' }
      end
    end
  end

  def github(files = { 'lib/package.rb' => PACKAGE, 'bin/tool.py' => SCRIPT }, symlinks = [])
    FakeGitHub.new(files, [], symlinks)
  end

  def resolved_body(links, body, client = github)
    Shaka::Walkthrough::CodeLinks.resolve(body, { 'head' => HEAD, 'code_links' => links }, client)
  end
end

class CodeLinksTest < Minitest::Test
  include CodeLinksFixtures

  def test_block_link_covers_a_method_through_its_closing_line
    body = resolved_body({ 'stage' => { 'path' => 'lib/package.rb', 'from' => 'def stage', 'block' => true } },
                         'See [`stage`](code:stage).')
    assert_equal "See [`stage`](#{BLOB}/lib/package.rb#L6-L9).", body
  end

  def test_block_link_keeps_same_indentation_clauses_before_the_closer
    source = "def run\n  perform\nrescue Error\n  recover\nensure\n  close\nend # run\n" \
             "function f() {\n  if (x) {\n    a()\n  } else {\n    b()\n  }\n}\n"
    links = { 'run' => { 'path' => 'lib/run.rb', 'from' => 'def run', 'block' => true },
              'if' => { 'path' => 'lib/run.rb', 'from' => 'if (x)', 'block' => true } }
    body = resolved_body(links, '[run](code:run) [if](code:if)', github('lib/run.rb' => source))
    assert_equal "[run](#{BLOB}/lib/run.rb#L1-L7) [if](#{BLOB}/lib/run.rb#L9-L13)", body
  end

  def test_to_link_ends_at_the_first_matching_line_after_from
    body = resolved_body({ 'flow' => { 'path' => 'lib/package.rb', 'from' => 'def stage', 'to' => 'rename' } },
                         '[flow](code:flow)')
    assert_equal "[flow](#{BLOB}/lib/package.rb#L6-L12)", body
  end

  def test_to_text_on_the_starting_line_does_not_end_the_range
    body = resolved_body({ 'x' => { 'path' => 'lib/package.rb', 'from' => 'def prepare', 'to' => 'end' } },
                         '[x](code:x)', github('lib/package.rb' => PACKAGE.sub('prepare(root)', 'prepare(send_end)')))
    assert_equal "[x](#{BLOB}/lib/package.rb#L2-L4)", body
  end

  def test_block_link_continues_past_a_multiline_signature
    source = "def call(\n  root\n)\n  run(root)\nend\n"
    body = resolved_body({ 'x' => { 'path' => 'lib/call.rb', 'from' => 'def call', 'block' => true } },
                         '[x](code:x)', github('lib/call.rb' => source))
    assert_equal "[x](#{BLOB}/lib/call.rb#L1-L5)", body
  end

  def test_link_without_to_or_block_names_one_line
    body = resolved_body({ 'call' => { 'path' => 'lib/package.rb', 'from' => 'copy(root)' } }, '[call](code:call)')
    assert_equal "[call](#{BLOB}/lib/package.rb#L7)", body
  end

  def test_every_reference_resolves_and_each_file_is_fetched_once
    client = github
    links = { 'stage' => { 'path' => 'lib/package.rb', 'from' => 'def stage', 'block' => true },
              'publish' => { 'path' => 'lib/package.rb', 'from' => 'def publish', 'block' => true } }
    body = resolved_body(links, "Start at [s](code:stage).\n\n| Code |\n| --- |\n| [p](code:publish) |", client)
    assert_equal "Start at [s](#{BLOB}/lib/package.rb#L6-L9).\n\n| Code |\n| --- |\n" \
                 "| [p](#{BLOB}/lib/package.rb#L11-L13) |", body
    assert_equal ["repos/owner/repo/contents/lib?ref=#{HEAD}", "repos/owner/repo/contents/lib/package.rb?ref=#{HEAD}"],
                 client.requests
  end

  def test_code_spans_and_fences_keep_link_examples_literally
    example = "Write `[label](code:NAME)` or ``[a](code:b)``:\n\n```json\n[x](code:other)\n```\n\n" \
              "~~~text\n~~~not a closing fence\n[y](code:example)\n~~~~\n"
    assert_equal example, resolved_body({}, example)
  end

  def test_content_without_code_links_is_unchanged
    body = 'See [x](code:x).'
    assert_same body, Shaka::Walkthrough::CodeLinks.resolve(body, { 'head' => HEAD }, github)
  end
end

class CodeLinksRefusalTest < Minitest::Test
  include CodeLinksFixtures

  # The method closer sits deeper than a block would expect, so only the class closer is left.
  REFUSALS = { 'lib/package.rb' => PACKAGE, 'bin/tool.py' => SCRIPT,
               'lib/worker.rb' => "class Worker\n  def run\n    work\n      end\nend\n" }.freeze

  def test_ambiguous_or_missing_text_refuses_publication
    { { 'path' => 'lib/package.rb', 'from' => 'def ' } => 'matches 3 lines',
      { 'path' => 'lib/package.rb', 'from' => 'def absent' } => 'matches 0 lines',
      { 'path' => 'lib/package.rb', 'from' => 'def publish', 'to' => 'def stage' } => 'no line after',
      { 'path' => 'bin/tool.py', 'from' => 'def first', 'block' => true } => 'use to text',
      { 'path' => 'lib/worker.rb', 'from' => 'def run', 'block' => true } => 'use to text' }.each do |link, message|
      error = assert_raises(Shaka::Error) { resolved_body({ 'x' => link }, '[x](code:x)', github(REFUSALS)) }
      assert_includes error.message, message
      assert_includes error.message, 'code link x'
    end
  end

  def test_unrecognized_targets_and_string_booleans_are_refused
    link = { 'path' => 'lib/package.rb', 'from' => 'def stage' }
    cases = { '[run](code:Class#run)' => [{ 'x' => link }, 'undefined code link Class#run'],
              '[x](code:x)' => [{ 'x' => link.merge('block' => 'false') }, 'non-boolean block'] }
    cases.each do |body, (links, message)|
      error = assert_raises(Shaka::Error) { resolved_body(links, body) }
      assert_includes error.message, message
    end
  end

  def test_undefined_reference_and_invalid_definitions_are_refused
    link = { 'path' => 'lib/package.rb', 'from' => 'def stage' }
    [[{ 'x' => link }, '[y](code:y)', 'undefined code link y'],
     [{ 'x' => link.merge('to' => 'end', 'block' => true) }, '[x](code:x)', 'either to or block'],
     [{ 'x' => link.merge('path' => '../secret') }, '[x](code:x)', 'repository-relative path'],
     [{ 'x' => { 'path' => 'lib/package.rb' } }, '[x](code:x)', 'from text'],
     [[], '[x](code:x)', 'code_links must be an object']].each do |links, body, message|
      error = assert_raises(Shaka::Error) { resolved_body(links, body) }
      assert_includes error.message, message
    end
  end

  def test_symlinked_path_is_refused_because_its_permalink_shows_the_link
    # The contents API would return the target's text for the link path.
    client = github({ 'lib/alias.rb' => PACKAGE, 'lib/package.rb' => PACKAGE }, ['lib/alias.rb'])
    error = assert_raises(Shaka::Error) do
      resolved_body({ 'x' => { 'path' => 'lib/alias.rb', 'from' => 'def stage' } }, '[x](code:x)', client)
    end
    assert_includes error.message, 'not a regular file'
  end

  def test_file_that_is_not_utf8_is_refused_cleanly
    client = github({ 'lib/image.png' => "\xFF\xD8def x\n".b })
    error = assert_raises(Shaka::Error) do
      resolved_body({ 'x' => { 'path' => 'lib/image.png', 'from' => 'def x' } }, '[x](code:x)', client)
    end
    assert_includes error.message, 'not valid UTF-8'
  end

  def test_unreadable_file_names_the_link
    error = assert_raises(Shaka::Error) do
      resolved_body({ 'x' => { 'path' => 'lib/missing.rb', 'from' => 'def x' } }, '[x](code:x)')
    end
    assert_includes error.message, 'code link x'
  end
end

class CodeLinksCommandTest < Minitest::Test
  COMMAND = File.expand_path('../skills/shaka/scripts/shaka', __dir__)

  def test_undefined_code_link_stops_the_walkthrough_before_github
    Dir.mktmpdir do |dir|
      sentinel = failing_gh(dir)
      content = File.join(dir, 'content.json')
      File.write(content, JSON.generate({ 'identity' => {}, 'summary' => '[it](code:missing)', 'code_links' => {} }))
      _output, error, status = Open3.capture3({ 'PATH' => "#{dir}:#{ENV.fetch('PATH')}" }, COMMAND, 'walkthrough',
                                              'owner/repo', '1', '--head', 'a' * 40, '--content-file', content)
      refute_predicate status, :success?
      assert_includes error, 'undefined code link missing'
      refute_path_exists sentinel
    end
  end

  def failing_gh(dir)
    sentinel = File.join(dir, 'called')
    File.write(File.join(dir, 'gh'), "#!/bin/sh\ntouch #{sentinel}\nexit 1\n")
    File.chmod(0o755, File.join(dir, 'gh'))
    sentinel
  end
end
