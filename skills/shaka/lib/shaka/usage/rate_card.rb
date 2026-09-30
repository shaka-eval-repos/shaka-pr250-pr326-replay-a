# frozen_string_literal: true

require 'open3'
require 'yaml'
require_relative '../error'
require_relative '../repository_config/duplicate_keys'

module Shaka
  # Checked rate-card data. The installed command prices with its own formulas.
  class RateCard
    PATH = 'skills/shaka/config/model-rates.yml'
    INSTALLED_PATH = File.expand_path("../../../config/#{File.basename(PATH)}", __dir__)
    PRICE = /\A(?:0|[1-9]\d*)(?:\.\d+)?\z/
    NAME = /\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,79}\z/
    DATE = /\A\d{4}-\d{2}-\d{2}\z/

    def self.installed
      @installed ||= load_file(INSTALLED_PATH, candidate: false)
    end

    def self.installed_file
      File.realpath(INSTALLED_PATH)
    rescue SystemCallError => e
      raise Error, "Installed rate card is unreadable: #{e.message}"
    end

    # Review stays on the installed card. Implementation uses the named checkout,
    # or a checkout whose rate card is a different file from the installed copy.
    def self.select(contribution:, explicit_root:)
      return installed unless contribution == 'implementation'

      root = checkout_root(explicit_root)
      root ? load_root(root) : installed
    end

    def self.checkout_root(explicit_root)
      return File.expand_path(explicit_root) if explicit_root

      root = repository_root(Dir.pwd)
      path = File.join(root, PATH)
      return unless File.file?(path)
      return if File.realpath(path) == installed_file

      root
    end

    def self.repository_root(start)
      output, status = Open3.capture2('git', '-C', start, 'rev-parse', '--show-toplevel')
      return start unless status.success?

      found = output.strip
      found.empty? ? start : found
    rescue SystemCallError => e
      raise Error, "Could not read the git checkout: #{e.message}"
    end
    private_class_method :checkout_root, :repository_root

    def self.load_root(root)
      path = File.join(root, PATH)
      raise Error, "Candidate rate card is missing: #{PATH}" unless File.file?(path)

      load_file(path, candidate: true)
    end

    def self.load_file(path, candidate:)
      source = File.read(path, encoding: 'UTF-8')
      RepositoryConfig::DuplicateKeys.check(source, filename: PATH)
      data = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
      raise Error, "#{PATH} must be a mapping" unless data.is_a?(Hash)

      new(Schema.check(data), candidate:)
    rescue Psych::Exception, KeyError, SystemCallError => e
      raise Error, rate_card_error(e)
    end
    private_class_method :load_file

    def self.rate_card_error(error)
      return "#{PATH} is missing #{error.key}" if error.is_a?(KeyError)
      return "Rate card is unreadable: #{error.message}" if error.is_a?(SystemCallError)

      "Invalid #{PATH}: #{error.message}"
    end
    private_class_method :rate_card_error

    attr_reader :label

    def initialize(data, candidate:)
      @data = data
      @label = candidate ? 'candidate checkout' : 'installed Shaka'
    end

    def openai_rate(model, mode) = dig('openai', 'models', model, mode)
    def openai_threshold = dig('openai', 'threshold')
    def openai_verified = dig('openai', 'verified')
    def openai_model?(model) = models('openai').key?(model.to_s)

    def cursor_rate(model, billing) = dig('cursor', 'models', model, billing)
    def cursor_threshold(model) = dig('cursor', 'models', model, 'threshold')
    def cursor_long_context(billing) = dig('cursor', 'long_context', billing)
    def cursor_model?(model, billing) = cursor_rate(model, billing)
    def cursor_verified = dig('cursor', 'verified')

    def anthropic_prices(model) = dig('anthropic', 'models', model, 'prices')
    def anthropic_fast?(model) = dig('anthropic', 'models', model, 'fast') == true
    def anthropic_verified = dig('anthropic', 'verified')
    def anthropic_model?(name) = models('anthropic').key?(name.to_s)

    def anthropic_name(routed, configured, speed)
      names = [routed, configured].map(&:to_s)
      names.map! { |name| name.delete_suffix('-fast') } if speed == 'fast'
      names.find { |name| anthropic_model?(name) }
    end

    def anthropic_speed?(model, speed)
      return false unless model

      speed == 'standard' || (speed == 'fast' && anthropic_fast?(model))
    end

    private

    def models(provider) = @data.fetch(provider).fetch('models')

    def dig(*keys)
      @data.dig(*keys.map(&:to_s))
    end

    # Closed schema: a key the installed loader does not know fails the report.
    class Schema
      PROVIDERS = %w[openai cursor anthropic].freeze

      def self.check(data) = new(data).check

      def initialize(data) = @data = data

      def check
        unexpected = @data.keys - PROVIDERS
        raise Error, "unknown rate-card section: #{unexpected.first}" if unexpected.any?

        missing = PROVIDERS - @data.keys
        raise Error, "rate card is missing #{missing.first}" if missing.any?

        { 'openai' => openai, 'cursor' => cursor, 'anthropic' => anthropic }
      end

      private

      def openai
        section = mapping(@data.fetch('openai'), 'openai', %w[verified threshold models])
        { 'verified' => date(section.fetch('verified'), 'openai verified'),
          'threshold' => positive(section.fetch('threshold'), 'openai threshold'),
          'models' => models(section.fetch('models'), 'openai') { |entry, label| openai_model(entry, label) } }
      end

      def cursor
        section = mapping(@data.fetch('cursor'), 'cursor', %w[verified long_context models])
        { 'verified' => date(section.fetch('verified'), 'cursor verified'),
          'long_context' => long_context(section.fetch('long_context')),
          'models' => models(section.fetch('models'), 'cursor') { |entry, label| cursor_model(entry, label) } }
      end

      def anthropic
        section = mapping(@data.fetch('anthropic'), 'anthropic', %w[verified models])
        { 'verified' => date(section.fetch('verified'), 'anthropic verified'),
          'models' => models(section.fetch('models'), 'anthropic') { |entry, label| anthropic_model(entry, label) } }
      end

      def openai_model(entry, label)
        fields = mapping(entry, label, %w[credits api])
        { 'credits' => prices(fields.fetch('credits'), 3, "#{label} credits"),
          'api' => prices(fields.fetch('api'), 3, "#{label} api") }
      end

      def cursor_model(entry, label)
        fields = mapping(entry, label, %w[standard fast threshold])
        priced = { 'standard' => prices(fields.fetch('standard'), 3, "#{label} standard"),
                   'fast' => prices(fields.fetch('fast'), 3, "#{label} fast") }
        priced['threshold'] = positive(fields.fetch('threshold'), "#{label} threshold") if fields.key?('threshold')
        priced
      end

      def anthropic_model(entry, label)
        fields = mapping(entry, label, %w[prices fast])
        priced = { 'prices' => prices(fields.fetch('prices'), 5, "#{label} prices") }
        priced['fast'] = boolean(fields.fetch('fast'), "#{label} fast") if fields.key?('fast')
        priced
      end

      def models(value, provider)
        table = mapping(value, "#{provider} models")
        table.each_with_object({}) do |(name, entry), priced|
          raise Error, "invalid model name: #{name}" unless name.match?(NAME)

          priced[name] = yield(entry, name)
        end
      end

      def mapping(value, label, allowed = nil)
        raise Error, "#{label} must be a mapping" unless value.is_a?(Hash)
        raise Error, "#{label} keys must be strings" unless value.keys.all?(String)

        extra = allowed ? value.keys - allowed : []
        raise Error, "unknown rate-card key: #{extra.first}" if extra.any?

        value
      end

      def long_context(value)
        fields = mapping(value, 'cursor long_context', %w[standard fast])
        { 'standard' => positive(fields.fetch('standard'), 'cursor long_context standard'),
          'fast' => positive(fields.fetch('fast'), 'cursor long_context fast') }
      end

      def prices(value, count, label)
        raise Error, "#{label} must be #{count} prices" unless value.is_a?(Array) && value.size == count
        raise Error, "#{label} has an invalid price" unless price_list?(value)

        value
      end

      def price_list?(value)
        value.all? { |item| item.is_a?(String) && item.match?(PRICE) }
      end

      def date(value, label)
        raise Error, "#{label} must be YYYY-MM-DD" unless value.is_a?(String) && value.match?(DATE)

        value
      end

      def positive(value, label)
        raise Error, "#{label} must be a positive integer" unless value.is_a?(Integer) && value.positive?

        value
      end

      def boolean(value, label)
        raise Error, "#{label} must be true or false" unless [true, false].include?(value)

        value
      end
    end
  end
end
