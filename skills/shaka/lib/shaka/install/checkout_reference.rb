# frozen_string_literal: true

require 'json'
require 'shellwords'
require 'uri'

module Shaka
  module Install
    # Distinguishes the source's absolute path from a suffix of another path.
    module CheckoutReference
      LOCAL_FILE_HOSTS = [nil, '', 'localhost'].freeze

      private

      def references_checkout?(content, checkouts)
        checkouts.any? { |checkout| checkout_reference?(content, checkout) }
      end

      def checkout_reference?(content, checkout)
        return true if literal_checkout_reference?(content, checkout)
        return true if encoded_file_url_reference?(content, checkout)
        return true if encoded_json_checkout_reference?(content, checkout)

        escaped = Shellwords.escape(checkout)
        escaped != checkout && literal_checkout_reference?(content, escaped)
      end

      def encoded_json_checkout_reference?(content, checkout)
        return true if content.include?('\\/') && literal_checkout_reference?(content.gsub('\\/', '/'), checkout)

        content.include?('\\u') && json_checkout_reference?(content, checkout)
      end

      def json_checkout_reference?(content, checkout)
        json_value_references_checkout?(JSON.parse(content), checkout)
      rescue JSON::ParserError
        false
      end

      def json_value_references_checkout?(value, checkout)
        case value
        when Hash then json_value_references_checkout?(value.to_a.flatten(1), checkout)
        when Array then value.any? { |entry| json_value_references_checkout?(entry, checkout) }
        when String then decoded_string_reference?(value.b, checkout)
        else false
        end
      end

      def decoded_string_reference?(value, checkout)
        literal_checkout_reference?(value, checkout) || encoded_file_url_reference?(value, checkout)
      end

      def encoded_file_url_reference?(content, checkout)
        content.scan(/file:[^\s<>"'`)\]]+/i).any? do |url|
          uri = URI.parse(url)
          next false unless local_file_uri?(uri)

          path = URI::DEFAULT_PARSER.unescape(uri.path)
          next false unless path.start_with?('/')

          path = File.expand_path(path)
          path == checkout || path.start_with?("#{checkout}/")
        rescue URI::InvalidURIError, ArgumentError
          false
        end
      end

      def local_file_uri?(uri)
        uri.is_a?(URI::File) && LOCAL_FILE_HOSTS.include?(uri.host&.downcase) && uri.path
      end

      def literal_checkout_reference?(content, checkout)
        offset = 0
        while (index = content.index(checkout, offset))
          return true if boundary_before?(content, index) && boundary_after?(content, index + checkout.bytesize)

          offset = index + 1
        end
        false
      end

      def boundary_after?(content, index)
        following = content.getbyte(index)
        return true if following == '/'.ord || !path_byte?(following)

        (following == '.'.ord || following == '-'.ord) && !path_byte?(content.getbyte(index + 1))
      end

      def boundary_before?(content, index)
        previous = content.getbyte(index - 1) unless index.zero?
        !path_byte?(previous) || local_file_url?(content, index)
      end

      def local_file_url?(content, index)
        (index >= 7 && content.byteslice(index - 7, 7).downcase == 'file://') ||
          (index >= 16 && content.byteslice(index - 16, 16).downcase == 'file://localhost')
      end

      def path_byte?(byte)
        byte && (byte >= 128 || byte.chr.match?(%r{[A-Za-z0-9_./~$-]}))
      end
    end
  end
end
