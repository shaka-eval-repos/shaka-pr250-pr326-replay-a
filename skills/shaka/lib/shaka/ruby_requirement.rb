# frozen_string_literal: true

# Loading this file checks the running Ruby, so an older Ruby stops with a fix before it
# parses code written for Ruby 3.4. Keep it parseable by any Ruby. The launcher preloads
# it with -r, and a symlinked skill path can load it twice, so a second load does nothing.
return if defined?(Shaka::RubyRequirement)

module Shaka
  # Names the Ruby Shaka needs and stops an older one.
  module RubyRequirement
    MINIMUM = '3.4'

    def self.check!(version = RUBY_VERSION)
      return if (version.split('.').map(&:to_i) <=> MINIMUM.split('.').map(&:to_i)) >= 0

      # Kernel#warn is silent under -W0, and this message is the only guidance an old Ruby gets.
      $stderr.write "Shaka needs Ruby #{MINIMUM} or newer; this Ruby is #{version}. " \
                    "Rerun bin/install with Ruby #{MINIMUM}, or set SHAKA_RUBY to a Ruby #{MINIMUM} interpreter.\n"
      exit 1
    end
  end
end

Shaka::RubyRequirement.check!
