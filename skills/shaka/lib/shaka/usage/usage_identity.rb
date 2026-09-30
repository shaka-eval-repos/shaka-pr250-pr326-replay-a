# frozen_string_literal: true

require 'digest'
require 'json'
require 'time'
require_relative 'options'

module Shaka
  # Hidden identity that lets a later host tell this report from a refreshed snapshot.
  module UsageIdentity
    private

    def timestamps
      @responses.filter_map do |record|
        stamp = record['timestamp']
        next unless stamp.is_a?(String) && stamp.match?(UsageOptions::ISO_TIME)

        Time.iso8601(stamp).utc.iso8601(stamp[/\.(\d+)/, 1]&.size || 0)
      rescue ArgumentError
        nil
      end
    end

    # Digests let a later host match responses and sources without publishing local paths or IDs.
    # Complete means every selected response had at least one readable token counter. It does not
    # say which fields were read, because readers legitimately leave some fields UNKNOWN.
    def record_identity
      { 'host' => @options[:host], 'sources' => @options[:files].map { |file| digest(file) }.uniq,
        'responses' => measured_responses.map { |id| response_digest(id) }, 'contribution' => @options[:contribution],
        'commits' => @options[:commit].split(','), 'complete' => complete? }.merge(interval_fields)
    end

    def complete? = measured_responses.size == @selected_responses.size

    # A Claude print result is keyed by its session, which resumed runs share, so its identity
    # also covers its counters: separate runs differ, while a copy or re-read of one run matches.
    def response_digest(id)
      record = @selected_responses[id]
      digest(record['aggregate'] ? "#{id}\0#{JSON.generate(record['usage'])}" : id)
    end

    def interval_fields
      from, to = timestamps.minmax_by { |stamp| Time.iso8601(stamp) }
      { 'from' => from || 'UNKNOWN', 'to' => to || 'UNKNOWN' }
    end

    # A response without a readable token counter cannot stand in for one an earlier report measured.
    def measured_responses
      fields = Usage::METRIC_FIELDS.map(&:last)
      @selected_responses.filter_map do |id, record|
        usage = record['usage']
        id if usage.is_a?(Hash) && usage.values_at(*fields).any? { |value| value.is_a?(Integer) && value >= 0 }
      end
    end

    def digest(value) = Digest::SHA256.hexdigest("#{@options[:host]}\0#{value}")[0, 12]
  end
end
