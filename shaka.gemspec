# frozen_string_literal: true

require_relative 'skills/shaka/lib/shaka/version'

Gem::Specification.new do |spec|
  spec.name = 'shaka'
  spec.version = Shaka::VERSION
  spec.summary = 'Give your agent a task. Get a verified, explained pull request.'
  spec.authors = ['ShakaCode']
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/shakacode/shaka'
  spec.required_ruby_version = '>= 3.4'
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['documentation_uri'] = "#{spec.homepage}/blob/main/docs/getting-started.md"
  spec.files = Dir['skills/rct/SKILL.md', 'skills/mct-claude/SKILL.md', 'skills/rct-claude/SKILL.md',
                   'skills/shaka/SKILL.md', 'skills/shaka/references/*.md',
                   'skills/shaka/config/*.yml', 'skills/shaka/config/*.md', 'skills/shaka/lib/**/*.rb',
                   'skills/shaka/scripts/*', 'bin/install', 'exe/*', 'docs/**/*.md',
                   'contributing/**/*.md',
                   'README.md', 'CONTRIBUTING.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = %w[shaka shaka-install]
  spec.require_paths = ['skills/shaka/lib']
end
