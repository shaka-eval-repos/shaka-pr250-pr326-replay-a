# frozen_string_literal: true

require 'digest'
require 'json'
require_relative '../../error'

module Shaka
  module Configuration
    # Canonical typed JSON for versioned fingerprint components.
    module FingerprintCanonical
      module_function

      def digest(label, value)
        Digest::SHA256.hexdigest(JSON.generate(normalize('schema' => 1, 'component' => label, 'value' => value)))
      rescue JSON::GeneratorError, Encoding::InvalidByteSequenceError => e
        raise Error, "Fingerprint input cannot be encoded: #{e.class}"
      end

      def normalize(value)
        case value
        when Hash then normalize_hash(value)
        when Array then value.map { |entry| normalize(entry) }
        when String then normalize_string(value)
        when Integer, TrueClass, FalseClass, NilClass then value
        when Float then normalize_float(value)
        else raise Error, "Unsupported fingerprint value #{value.class}"
        end
      end

      def normalize_hash(value)
        raise Error, 'Fingerprint keys must be strings' unless value.keys.all?(String)

        value.keys.sort.to_h { |key| [key, normalize(value.fetch(key))] }
      end

      def normalize_string(value)
        encoded = value.encode(Encoding::UTF_8)
        raise Error, 'Fingerprint input has invalid UTF-8' unless encoded.valid_encoding?

        encoded
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        raise Error, 'Fingerprint input has invalid UTF-8'
      end

      def normalize_float(value)
        raise Error, 'Fingerprint input has nonfinite number' unless value.finite?

        value
      end

      def freeze_tree(value)
        case value
        when Hash then value.each do |key, item|
          key.freeze
          freeze_tree(item)
        end
        when Array then value.each { |item| freeze_tree(item) }
        end
        value.freeze
      end
    end
  end
end
