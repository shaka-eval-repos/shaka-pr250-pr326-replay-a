# frozen_string_literal: true

require_relative '../error'

module Shaka
  # Carries earlier usage reports when the new description supplies structured records.
  module UsageRecordCarry
    module_function

    def structured_usage(content)
      usage = content.is_a?(Hash) ? content['usage'] : nil
      usage if usage.is_a?(Hash)
    end

    # Only carry may fill `carried`, and only from a same-repository PR body it checked.
    def without_caller_carry(content)
      usage = structured_usage(content)
      usage ? content.merge('usage' => usage.except('carried')) : content
    end

    def apply(records, content, usage, existing, stats)
      fresh = Array(usage['records']).map { |fields| identity!(without_columns(fields)) }
      region = records.managed_region(existing)
      return [content, stats] unless region

      kept = records.carried(region, '', stats, fresh)
      return [content, stats] if kept.empty?

      [content.merge('usage' => usage.except('carried').merge('carried' => kept.join("\n\n"))), stats]
    end

    # A report that read no source records nothing about its commits. Once a complete report from
    # the same host measured the same contribution and commits, the empty one only adds noise.
    def read_nothing_covered?(old, reports)
      return false unless old['sources'].empty? && old['responses'].empty?

      reports.any? do |new|
        new['host'] == old['host'] && new['complete'] == true && new['responses'].any? &&
          UsageRecords.same_attribution?(old, new)
      end
    end

    TOKEN = /\A[A-Za-z0-9][A-Za-z0-9._:-]{0,79}\z/
    STAMP = /\A(?:UNKNOWN|\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z)\z/
    CONTRIBUTIONS = %w[implementation review integration shared-planning].freeze

    # Only the checked fields are kept, since the identity is written into an HTML comment.
    def identity(fields)
      fields.slice(*UsageRecords::FIELDS) if shape?(fields) && route?(fields) && lists?(fields)
    end

    def shape?(fields)
      fields.is_a?(Hash) && UsageRecords::FIELDS.all? { |key| fields.key?(key) }
    end

    def route?(fields)
      token?(fields['host']) && CONTRIBUTIONS.include?(fields['contribution']) &&
        [true, false].include?(fields['complete']) && stamp?(fields['from']) && stamp?(fields['to'])
    end

    def lists?(fields)
      array_of(fields['commits']) { |commit| commit.match?(/\A[0-9a-f]{40}\z/) } &&
        %w[sources responses].all? { |key| array_of(fields[key]) { |item| token?(item) } }
    end

    def token?(value) = value.is_a?(String) && value.match?(TOKEN)
    def stamp?(value) = value.is_a?(String) && value.match?(STAMP)

    def array_of(value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) && yield(item) }
    end

    def identity!(fields)
      identity(fields) || raise(Error, 'Publication usage record is missing identity fields.')
    end

    def without_columns(fields)
      fields.is_a?(Hash) ? fields.except('columns') : fields
    end
  end
end
