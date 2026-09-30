# frozen_string_literal: true

# Keeps candidate-owned executables and script interpreters out of command PATHs.

require_relative '../error'
require_relative 'executable'
require_relative 'shebang'

module Shaka
  # Screens command lookup paths before candidate data can influence a process.
  module LocalReviewPathGuard
    def self.safe_path(path, candidate_root:, drop_candidate: false)
      entries = path.split(File::PATH_SEPARATOR, -1)
      entries.filter_map do |entry|
        normalized_path_entry(entry, candidate_root, drop_candidate)
      end
             .join(File::PATH_SEPARATOR)
    end

    def self.normalized_path_entry(entry, candidate_root, drop_candidate)
      directory = File.expand_path(entry.empty? ? '.' : entry)
      return directory unless File.directory?(directory)

      state = candidate_path_state(File.realpath(directory), candidate_root)
      return if state == :uninspectable
      return directory if state == :safe
      return if drop_candidate

      raise Shaka::Error, 'PATH entry resolves inside candidate checkout'
    end

    def self.candidate_path_state(directory, candidate_root)
      return :candidate if LocalReviewExecutable.candidate_owned?(directory, candidate_root)

      linked = candidate_link_in_directory?(directory, candidate_root)
      return :uninspectable if linked == :uninspectable

      linked ? :candidate : :safe
    end

    def self.candidate_link_in_directory?(directory, candidate_root)
      Dir.children(directory).any? do |name|
        path = File.join(directory, name)
        File.symlink?(path) && candidate_link?(path, candidate_root)
      end
    rescue SystemCallError
      :uninspectable # Omit a PATH directory that cannot be inspected.
    end

    def self.candidate_link?(path, candidate_root)
      LocalReviewExecutable.candidate_owned?(File.realpath(path), candidate_root)
    rescue Errno::ENOENT
      false # A dangling link cannot launch candidate code; inspect the remaining links.
    end

    def self.safe_executable(path, name, candidate_root)
      selected = first_executable(path.split(File::PATH_SEPARATOR, -1), name, candidate_root, true)
      return unless selected

      real_directory = File.dirname(File.realpath(selected))
      linked = candidate_link_in_directory?(real_directory, candidate_root)
      raise Shaka::Error, "#{name} wrapper directory cannot be inspected" if linked == :uninspectable
      raise Shaka::Error, "#{name} wrapper directory contains candidate-backed links" if linked

      interpreter_name(selected, name, candidate_root)
      selected
    end

    def self.first_executable(entries, name, candidate_root, drop_candidate)
      entries.each do |entry|
        directory = File.expand_path(entry.empty? ? '.' : entry)
        executable = File.join(directory, name)
        next unless File.file?(executable) && File.executable?(executable)
        next if drop_candidate && candidate_executable?(directory, executable, candidate_root)

        return executable
      end
      nil
    end

    def self.candidate_executable?(directory, executable, candidate_root)
      LocalReviewExecutable.candidate_owned?(File.realpath(directory), candidate_root) ||
        LocalReviewExecutable.candidate_owned?(File.realpath(executable), candidate_root)
    end

    def self.interpreter_name(executable, name, candidate_root)
      return unless (interpreter = shebang_interpreter(executable))

      if !interpreter.start_with?('/') && interpreter.include?(File::SEPARATOR)
        raise Shaka::Error, "#{name} interpreter uses a relative path"
      end

      unsafe = interpreter.start_with?('/') && candidate_interpreter?(interpreter, candidate_root)
      raise Shaka::Error, "#{name} interpreter resolves inside candidate checkout" if unsafe

      File.basename(interpreter)
    end

    def self.candidate_interpreter?(interpreter, candidate_root)
      LocalReviewExecutable.candidate_owned?(File.realpath(interpreter), candidate_root)
    rescue SystemCallError
      false # A missing interpreter cannot launch candidate code.
    end

    def self.shebang_interpreter(executable) = LocalReviewShebang.interpreter(executable)
  end
end
