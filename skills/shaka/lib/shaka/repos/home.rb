# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'yaml'
require_relative '../error'

module Shaka
  class Repos
    # Install-local files for registered roots and the rebuilt catalog.
    class Home
      CONFIG_NAME = 'repos.yml'
      CATALOG_NAME = 'catalog.json'

      def initialize(path)
        @path = path
      end

      def add(root)
        roots = (roots_list + [File.realpath(root)]).uniq
        FileUtils.mkdir_p(@path)
        File.write(config_path, YAML.dump({ 'roots' => roots }))
        roots
      end

      def write_catalog(catalog)
        FileUtils.mkdir_p(@path)
        File.write(catalog_path, "#{JSON.pretty_generate(catalog)}\n")
      end

      def roots_list
        return [] unless File.file?(config_path)

        data = YAML.safe_load(File.read(config_path, encoding: 'UTF-8'),
                              permitted_classes: [], permitted_symbols: [], aliases: false)
        roots = data.is_a?(Hash) ? data['roots'] : nil
        raise Error, "#{CONFIG_NAME} roots must be a list of directories" unless roots.is_a?(Array)

        roots.map(&:to_s)
      end

      def resolve(root)
        File.realpath(root)
      end

      def config_path = File.join(@path, CONFIG_NAME)

      def catalog_path = File.join(@path, CATALOG_NAME)
    end
  end
end
