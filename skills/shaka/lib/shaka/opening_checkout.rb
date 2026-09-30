# frozen_string_literal: true

# Finds the candidate checkout boundary without invoking its Git executable.

module Shaka
  # Finds the outer checkout directory without launching Git.
  module OpeningCheckout
    module_function

    def root(dir)
      directory = File.realpath(dir)
      directory = File.dirname(directory) until File.exist?(File.join(directory, '.git')) ||
                                                directory == File.dirname(directory)
      File.exist?(File.join(directory, '.git')) ? directory : nil
    rescue SystemCallError
      nil
    end
  end
end
