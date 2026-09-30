# frozen_string_literal: true

# Reads a wrapper's shebang without letting relative interpreters or env overrides run.

require_relative '../error'

module Shaka
  # Names the interpreter a wrapper would launch, rejecting ambiguous forms.
  module LocalReviewShebang
    module_function

    def interpreter(executable)
      line = shebang_line(executable)
      return unless line

      words = line.delete_prefix('#!').split
      command = words.first
      return unless command

      raise Shaka::Error, 'Relative shebang interpreter' unless command.start_with?('/')

      File.basename(command) == 'env' ? env_interpreter(line, words.drop(1)) : command
    end

    def shebang_line(executable)
      line = File.open(executable, 'rb') { |file| file.read(256).to_s.lines.first.to_s }
      line if line.start_with?('#!')
    end

    def env_interpreter(line, arguments)
      raise Shaka::Error, 'Unsupported env shebang quoting' if line.match?(/['"\\$]/)

      validated_env_command(env_arguments(arguments).first)
    end

    def env_arguments(arguments)
      arguments.shift if arguments.first == '-S'
      arguments[0] = arguments.first.delete_prefix('-S') if arguments.first&.start_with?('-S')
      arguments
    end

    def validated_env_command(interpreter)
      raise Shaka::Error, 'env shebang sets environment variables' if interpreter&.match?(/\A[A-Za-z_]\w*=/)
      raise Shaka::Error, 'Cannot determine env shebang interpreter' if interpreter.nil? || interpreter.start_with?('-')

      interpreter
    end
  end
end
