# frozen_string_literal: true

require_relative '../error'

module Shaka
  # Failure text for `shaka usage`, kept beside the command so the runner stays small.
  module UsageErrors
    module_function

    def message(error)
      return "shaka usage: #{error.message}" if error.is_a?(Error)

      'shaka usage: invalid options; use shaka usage --help'
    end
  end
end
