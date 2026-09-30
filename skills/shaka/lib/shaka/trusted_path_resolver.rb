# frozen_string_literal: true

require 'open3'
require 'pathname'
require_relative 'error'

module Shaka
  # Resolves a repository path against one immutable Git tree using filesystem symlink semantics.
  class TrustedPathResolver
    SYMLINK = %w[120000 blob].freeze
    TREE = %w[040000 tree].freeze
    MAX_SYMLINKS = 40

    GIT = ->(*arguments) { Open3.capture3('git', *arguments) }

    # `git` takes Git arguments and returns stdout, stderr, and status. The local review runner passes
    # one that uses its vetted executable and timeout; other callers use Git from PATH.
    def initialize(root:, sha:, git: GIT)
      @root = root
      @sha = sha
      @git = git
    end

    def entry(path)
      parent = File.dirname(path)
      treeish = parent == '.' ? @sha : "#{@sha}:#{parent}"
      output, _error, status = @git.call('-C', @root, 'ls-tree', '-z', treeish)
      return unless status.success? && !output.empty?

      parse_entry(output, File.basename(path))
    end

    def resolve(path)
      @components = path.split('/', -1)
      @resolved = []
      @symlink_hops = 0
      missing = catch(:missing) { walk }
      return missing if missing

      final = @resolved.join('/')
      [final, entry(final)]
    end

    private

    def parse_entry(output, name)
      row = output.split("\0").find { |candidate| candidate.split("\t", 2).last == name }
      return unless row

      metadata, = row.split("\t", 2)
      mode, type, = metadata.split
      [mode, type]
    end

    def walk
      consume(@components.shift) until @components.empty?
      nil
    end

    def consume(component)
      return if ignorable_component?(component)
      return ascend if component == '..'

      candidate = (@resolved + [component]).join('/')
      command_entry = entry(candidate)
      throw(:missing, [candidate, nil]) unless command_entry
      unless command_entry == SYMLINK
        throw(:missing, [candidate, nil]) if @components.any? && command_entry != TREE
        return @resolved << component
      end

      follow(candidate)
    end

    def ignorable_component?(component) = component.empty? || component == '.'

    def ascend
      raise Error, "Trusted command path at #{@sha} must stay inside the repository" if @resolved.empty?

      @resolved.pop
    end

    def follow(path)
      @symlink_hops += 1
      if @symlink_hops > MAX_SYMLINKS
        raise Error, "Trusted command symlink cycle or depth exceeded at #{path} in #{@sha}"
      end

      target = symlink_target(path)
      raise Error, "#{path} at #{@sha} must target a file inside the repository" if Pathname.new(target).absolute?

      @components.unshift(*target.split('/', -1))
    end

    def symlink_target(path)
      target, error, status = @git.call('-C', @root, 'show', "#{@sha}:#{path}")
      raise Error, "Cannot read trusted symlink #{path} at #{@sha}: #{error.strip}" unless status.success?

      target
    end
  end
end
