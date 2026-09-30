# frozen_string_literal: true

require 'shaka/doctor'

# Builds a Doctor whose every outside dependency is supplied, so each test states exactly
# the machine it describes instead of inheriting the one it runs on.
module DoctorHelper
  INSTALLED = "gh version 2.64.0 (2026-09-01)\n"
  WRITABLE = '{"nameWithOwner":"owner/repo","viewerPermission":"WRITE"}'
  DEFAULTS = { root: nil, environment: { 'SHAKA_MACHINE_ALIAS' => 'm5' }, responses: {}, runner: nil,
               usage_files: nil, usage_source: nil, host_name: 'test-machine.local', host: 'claude-code',
               ruby_version: RUBY_VERSION, cursor_stop_hook: false }.freeze

  def doctor(**overrides)
    options = DEFAULTS.merge(overrides)
    subject = Shaka::Doctor.new(root: options[:root] || File.expand_path('..', __dir__),
                                host: options[:host], environment: options[:environment],
                                system: stub_system(options))
    [subject.report, subject.blocked?]
  end

  def stub_system(options)
    Shaka::Doctor::System.new(runner: options[:runner] || stub_gh(options[:responses]),
                              usage_source: options[:usage_source] || ->(_host) { options[:usage_files] || [__FILE__] },
                              host_name: options[:host_name], ruby_version: options[:ruby_version],
                              cursor_stop_hook: -> { options[:cursor_stop_hook] })
  end

  def check_names(report) = report.scan(/^\[\w+\] ([^\n]+?) —/).flatten.sort

  def stub_gh(responses)
    lambda do |argv, _chdir = nil|
      key = argv.include?('--version') ? :version : :view
      responses.fetch(key, key == :version ? [INSTALLED, '', true] : [WRITABLE, '', true])
    end
  end
end
