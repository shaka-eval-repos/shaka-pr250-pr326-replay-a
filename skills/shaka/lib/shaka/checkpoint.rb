# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'error'

module Shaka
  # Decides whether an intake already supplies the implementation checkpoint.
  class Checkpoint
    ACTIONS = {
      'value_not_established' => 'Reply ready if the value stated above holds. Reject it and the task stops here.',
      'recommendation_missing' => 'Make a model and effort recommendation, then rerun checkpoint.',
      'settings_unavailable' => 'Select an available model and effort, then reply ready.',
      'settings_conflict' => 'Resolve the requested and recommended settings, then reply ready.',
      'settings_unverified' => 'Confirm the active model and effort, then reply ready.',
      'immediate_start_not_authorized' => 'Reply ready to begin implementation.'
    }.freeze

    def self.run(arguments)
      path = content_path(arguments)
      return 0 unless path

      puts JSON.generate(new(content(path)).result)
      0
    rescue OptionParser::ParseError, JSON::ParserError, SystemCallError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def self.content_path(arguments)
      options = {}
      parser = option_parser(options)
      parser.parse!(arguments)
      puts parser if options[:help]
      return if options[:help]

      raise OptionParser::InvalidArgument, parser.to_s unless arguments.empty? && options[:path]

      options.fetch(:path)
    end

    def self.option_parser(options)
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka checkpoint --content-file PATH'
        flags.on('--content-file PATH', 'Checkpoint content as JSON') { |value| options[:path] = value }
        flags.on('-h', '--help', 'Show usage') { options[:help] = true }
      end
    end

    def self.content(path)
      parsed = JSON.parse(File.read(path, encoding: 'UTF-8'))
      raise Error, 'Checkpoint content must be an object.' unless parsed.is_a?(Hash)

      parsed
    end

    private_class_method :content_path, :option_parser, :content

    def initialize(content)
      @content = content
    end

    def result
      return { 'status' => 'proceed' } if proceed?

      reason = pause_reason
      { 'status' => 'pause', 'reason' => reason, 'action' => action(reason) }
    end

    private

    def proceed?
      value_established? && matching_settings? && active_settings? &&
        immediate_start? && settings_available?
    end

    # Absent means the user named the task, which already establishes its value.
    # Only an agent proposing work, or acting on an unverified report, sets this false.
    # A present non-boolean is a malformed verdict, not a quiet yes.
    def value_established?
      verdict = @content.fetch('value_established', true)
      [true, false].include?(verdict) ? verdict : raise(Error, 'Checkpoint value_established must be true or false.')
    end

    def matching_settings?
      recommendation_present? &&
        %w[model effort].all? do |setting|
          requested = @content["requested_#{setting}"]
          requested.nil? || (requested.is_a?(String) && requested.strip.empty?) ||
            requested == @content["recommended_#{setting}"]
        end
    end

    def active_settings?
      active_settings_reported? && @content['active_model'] == @content['recommended_model'] &&
        @content['active_effort'] == @content['recommended_effort']
    end

    def immediate_start? = @content['immediate_start'] == true

    def settings_available? = @content['settings_available'] == true

    def pause_reason
      return 'value_not_established' unless value_established?

      settings_pause_reason
    end

    def settings_pause_reason
      return 'recommendation_missing' unless recommendation_present?
      return 'settings_unavailable' unless settings_available?
      return 'settings_conflict' unless matching_settings?
      return 'settings_unverified' unless active_settings_reported?
      return 'settings_inactive' unless active_settings?
      return 'immediate_start_not_authorized' unless immediate_start?

      raise Error, 'Checkpoint has no pause reason.'
    end

    def active_settings_reported?
      %w[active_model active_effort].all? do |field|
        @content[field].is_a?(String) && !@content[field].strip.empty?
      end
    end

    def action(reason)
      if reason == 'settings_inactive'
        return format('Set the host to %<model>s with %<effort>s effort, then reply ready.',
                      model: @content['recommended_model'], effort: @content['recommended_effort'])
      end

      ACTIONS.fetch(reason) { raise Error, "Unknown checkpoint pause reason: #{reason}." }
    end

    def recommendation_present?
      %w[recommended_model recommended_effort].all? do |field|
        @content[field].is_a?(String) && !@content[field].strip.empty?
      end
    end
  end
end
