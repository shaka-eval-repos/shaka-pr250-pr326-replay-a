# frozen_string_literal: true

require 'ripper'

module Shaka
  module Install
    # Reads Shaka's product version from version.rb without executing it.
    module Version
      def self.read(path)
        value = declared_value(Ripper.sexp(File.read(path))) if File.file?(path)
        raise ArgumentError, 'Missing Shaka version' unless value
        raise ArgumentError, 'Invalid Shaka version' unless value.match?(/\A[A-Za-z0-9][A-Za-z0-9._+-]*\z/)

        value
      end

      def self.declared_value(syntax)
        body = module_body(syntax)
        return unless body&.all? { |node| node[0] == :void_stmt || literal_constant_assignment?(node) }

        assignments = body.select { |node| version_assignment?(node) }
        return unless assignments.one?

        literal_value(assignments.first[2])
      end

      def self.literal_value(node)
        case node
        in [:string_literal, [:string_content, [:@tstring_content, String => value, _]]]
          value
        else
          nil
        end
      end

      def self.module_body(syntax)
        modules = syntax&.dig(1)
        return unless modules.is_a?(Array) && modules.one? && shaka_module?(modules.first)

        modules.first.dig(2, 1)
      end

      def self.shaka_module?(node)
        node[0] == :module && node.dig(1, 0) == :const_ref && node.dig(1, 1, 1) == 'Shaka'
      end

      def self.version_assignment?(node)
        node[0] == :assign && node.dig(1, 0) == :var_field && node.dig(1, 1, 1) == 'VERSION'
      end

      def self.literal_constant_assignment?(node)
        node[0] == :assign && node.dig(1, 0) == :var_field && node.dig(1, 1, 0) == :@const &&
          literal_value(node[2])
      end

      private_class_method :declared_value, :literal_value, :module_body, :shaka_module?, :version_assignment?,
                           :literal_constant_assignment?
    end
  end
end
