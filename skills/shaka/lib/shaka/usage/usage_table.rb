# frozen_string_literal: true

module Shaka
  # Host-context fallback rows when a reader has no per-response records.
  module UsageTable
    private

    def rows
      groups = table_groups
      return "| Metric |\n| --- |" if groups.empty?

      headers = column_headers(groups.keys)
      lines = [line(['Metric', *headers]), line(['---'] * (headers.size + 1))]
      metric_cells(groups).each { |label, values| lines << line([label, *values]) }
      lines.join("\n")
    end

    def table_groups
      grouped = @responses.group_by { |record| record['configuration'] }
      grouped.empty? && context_row ? { context_row => [] } : grouped
    end

    def column_headers(configurations)
      labeled = configurations.map { |configuration| configuration.map { |value| safe(value) } }
      unique_labels(labeled) || sequence_labels(labeled)
    end

    def unique_labels(labeled)
      label_candidates(labeled).find { |names| names.uniq.size == names.size }
    end

    def label_candidates(labeled)
      [0, 1, 2].map { |index| labeled.map { |cells| cells[index] } } +
        [[0, 1], [0, 1, 3]].map { |indexes| join_cells(labeled, indexes) }
    end

    def join_cells(labeled, indexes)
      labeled.map { |cells| indexes.map { |index| cells[index] }.join(' ') }
    end

    def sequence_labels(labeled)
      labeled.map.with_index { |cells, index| "#{cells[0]}-#{index + 1}" }
    end

    def metric_cells(groups)
      configs = groups.keys.map { |configuration| configuration.map { |value| safe(value) } }
      settings = Usage::SETTING_LABELS.zip(configs.transpose)
      tokens = Usage::METRIC_FIELDS.map do |label, field|
        [label, groups.values.map { |group| total_field(group, field) }]
      end
      settings + tokens
    end

    def line(cells) = "| #{cells.join(' | ')} |"

    def total_field(group, field)
      values = group.map { |record| record['usage'].is_a?(Hash) ? record['usage'][field] : nil }
      countable?(values) ? values.sum : 'UNKNOWN'
    end

    def countable?(values)
      values.any? && values.all? { |value| value.is_a?(Integer) && value >= 0 }
    end

    def context_row
      return unless @inferred && @options[:turns].empty? && !@options[:since_time]

      @source.context_configuration if @source.respond_to?(:context_configuration)
    end

    def cost_responses
      return @responses unless @responses.empty? && context_row

      [{ 'configuration' => context_row, 'usage' => {} }]
    end

    def reviewer_coverage
      local = local_review_included? ? 'included below' : 'UNKNOWN'
      gaps = @source.gaps.uniq.join('; ')
      "Local adversarial reviewer usage: #{local}. External reviewer/tool-model usage: UNKNOWN. #{gaps}"
    end

    def local_review_included?
      return false unless @options[:contribution] == 'review'

      table_groups.any? do |_configuration, group|
        Usage::METRIC_FIELDS.any? { |_label, field| total_field(group, field).is_a?(Integer) }
      end
    end
  end
end
