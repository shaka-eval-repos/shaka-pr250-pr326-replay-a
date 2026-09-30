# frozen_string_literal: true

require 'psych'
require_relative '../error'

module Shaka
  class RepositoryConfig
    # Rejects ambiguous YAML before Psych silently keeps the last value.
    module DuplicateKeys
      module_function

      def check(source, filename:)
        stream = Psych.parse_stream(source, filename:)
        raise Error, "#{filename} must contain one YAML document" unless stream.children.length == 1

        visit(stream.children.first.root)
      end

      def visit(node)
        return unless node.respond_to?(:children) && node.children
        return node.children.each { |child| visit(child) } unless node.is_a?(Psych::Nodes::Mapping)

        visit_mapping(node)
      end

      def visit_mapping(node)
        keys = node.children.each_slice(2).map do |key, value|
          raise Error, 'YAML keys must be strings' unless key.is_a?(Psych::Nodes::Scalar)

          visit(value)
          key.value
        end
        duplicate = keys.tally.find { |_key, count| count > 1 }&.first
        raise Error, "duplicate key: #{duplicate}" if duplicate
      end
    end
  end
end
