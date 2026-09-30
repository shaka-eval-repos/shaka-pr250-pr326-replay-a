# frozen_string_literal: true

require 'rbconfig'
require 'shellwords'
require_relative 'install/tree'
require_relative 'install/source'
require_relative 'install/package'
require_relative 'install/links'

module Shaka
  # Installs a checkout independent copy and points one host's skills directory to it.
  class Installer
    RUBY_RECORD = '.shaka-ruby'

    def initialize(source_root:, skills_dir:, names:, rollback: nil, managed_dir: nil)
      @source_alias = File.expand_path(source_root)
      @source_root = File.realpath(source_root)
      @skills_dir = canonical(skills_dir)
      @names = names
      @rollback = rollback
      @managed = canonical(managed_dir || File.join(Dir.home, '.local/share/shaka/installs'))
      refuse_overlap
    end

    def run
      tree = Install::Tree.new(@names, source_root: @source_root, source_alias: @source_alias)
      source = Install::Source.new(@source_root, @names, tree)
      package = Install::Package.new(@managed, source, @names, tree)
      target = @rollback ? package.existing(@rollback) : package.prepare(@source_root)
      record_ruby
      Install::Links.new(@skills_dir, @managed, @source_root, @names).switch_all(target)
      announce(target)
    end

    def announce(target)
      puts "Package: #{File.basename(target)}"
      puts "Next: #{Shellwords.escape(File.join(@skills_dir, 'shaka/scripts/shaka'))} seam init --help"
    rescue SystemCallError, IOError
      nil
    end

    private

    # The installed helper starts with this Ruby, so the Ruby a project selects cannot stop it.
    def record_ruby
      path = File.join(@managed, RUBY_RECORD)
      staged = "#{path}.#{Process.pid}"
      File.write(staged, "#{File.realpath(RbConfig.ruby)}\n")
      File.chmod(0o644, staged)
      File.rename(staged, path)
    end

    def canonical(path)
      expanded = File.expand_path(path)
      ancestor = expanded
      ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor)
      File.expand_path(File.join(File.realpath(ancestor), expanded.delete_prefix(ancestor).delete_prefix('/')))
    end

    def refuse_overlap
      raise ArgumentError, 'Installation overlaps source checkout' if [@managed, @skills_dir].any? do |path|
        overlap?(path, @source_root)
      end
      raise ArgumentError, 'Managed and skills directories overlap' if overlap?(@managed, @skills_dir)
    end

    def overlap?(left, right)
      left == right || left.start_with?("#{right}/") || right.start_with?("#{left}/")
    end
  end
end
