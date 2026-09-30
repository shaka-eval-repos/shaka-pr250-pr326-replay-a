# frozen_string_literal: true

require 'json'
require 'rbconfig'
require 'tmpdir'

# Runs OpeningCheck against a fake claude CLI on a restricted PATH.
module OpeningCheckTestHelpers
  private

  def assert_invoked_outside(root, trace, opening)
    invocation = JSON.parse(File.read(trace))
    assert_includes invocation.fetch('prompt'), opening
    refute invocation.fetch('pwd').start_with?(File.realpath(root)), 'the model must not run inside the checkout'
  end

  def check(summary, root:, reviewer: 'anthropic/claude')
    Shaka::OpeningCheck.new(summary:, candidate_root: File.realpath(root), reviewer:,
                            cache_dir: File.join(File.dirname(root), 'cache')).call
  end

  def parse(character, reader_facing)
    { sentences: [{ character:, reader_facing:, action: 'acts', object: 'something',
                    hidden_actions: [], internal_terms: [] }] }
  end

  # The fake CLI lives in its own directory beside a separate candidate root.
  def with_claude(output, body: nil)
    Dir.mktmpdir do |dir|
      bin = File.join(dir, 'bin')
      root = File.join(dir, 'checkout')
      [bin, root].each { |path| Dir.mkdir(path) }
      trace = File.join(dir, 'trace.json')
      body ||= "puts #{JSON.generate(is_error: false, result: JSON.generate(output)).inspect}"
      write_claude(bin, trace, body)
      with_path(bin) { yield(root, trace, bin) }
    end
  end

  def write_claude(bin, trace, body)
    path = File.join(bin, 'claude')
    File.write(path, <<~RUBY)
      #!#{RbConfig.ruby}
      require 'json'
      File.write(#{trace.inspect}, JSON.generate({ args: ARGV, prompt: STDIN.read, pwd: Dir.pwd }))
      #{body}
    RUBY
    File.chmod(0o755, path)
  end

  def with_path(path)
    original = ENV.fetch('PATH', nil)
    ENV['PATH'] = path
    yield
  ensure
    ENV['PATH'] = original
  end
end
