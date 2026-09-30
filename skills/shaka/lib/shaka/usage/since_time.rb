# frozen_string_literal: true

require 'time'
require_relative '../error'
require_relative 'options'

module Shaka
  # Narrows a shared native session to responses at or after the current task began.
  module UsageSinceTime
    private

    def select_since_time
      raise Error, '--since-time cannot scope incomplete native sources.' unless @source.gaps.empty?

      cutoff = Time.iso8601(@options[:since_time])
      @selected_responses.select! do |_id, record|
        selected_after?(record, cutoff)
      end
      raise Error, '--since-time selected no responses; check the task start time.' if @selected_responses.empty?
    rescue ArgumentError
      raise Error, '--since-time needs an ISO 8601 timestamp with a timezone.'
    end

    def selected_after?(record, cutoff)
      time = response_time(record)
      threshold = record['timestamp'].include?('.') ? cutoff : Time.at(cutoff.to_i)
      time >= threshold
    end

    def response_time(record)
      raise Error, '--since-time cannot split an aggregate usage record.' if record['aggregate']

      timestamp = record['timestamp']
      return Time.iso8601(timestamp) if timestamp.is_a?(String) && timestamp.match?(UsageOptions::ISO_TIME)

      raise Error, '--since-time needs a zoned timestamp for every response.'
    rescue ArgumentError
      raise Error, '--since-time needs a zoned timestamp for every response.'
    end
  end
end
