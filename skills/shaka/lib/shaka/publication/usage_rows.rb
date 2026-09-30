# frozen_string_literal: true

require_relative 'usage_pricing'

module Shaka
  # What each shown column counts, for a reader who has not seen these reports before.
  module UsageGlossary
    MEANINGS = {
      'usd' => 'estimated cost at the provider’s published list prices, not an invoice',
      'credits' => 'estimated OpenAI Codex plan credits, the unit Codex plans meter usage in',
      'input' => 'tokens sent to the model; Codex and Cursor count cached input here too, Claude does not',
      'cached_input' => 'input read back from the provider’s prompt cache, which is billed at a lower rate',
      'output' => 'tokens the model wrote; Codex, Claude, and Pi count reasoning here too, OpenCode does not',
      'reasoning_output' => 'tokens the model spent reasoning before the answer',
      'cache_writes' => 'input stored in the prompt cache so later turns can reuse it'
    }.freeze

    module_function

    def for(metrics)
      lines = metrics.map { |key, label| "- **#{label}**: #{MEANINGS.fetch(key)}." }
      "<details>\n<summary>What the columns mean</summary>\n\n#{lines.join("\n")}\n\n</details>" unless lines.empty?
    end
  end

  # Rounds amounts for reading; the hidden record keeps the reported text.
  module UsageNumbers
    module_function

    def usd(value)
      return '<$0.01' if value.positive? && value < 0.005

      whole, cents = format('%.2f', value).split('.')
      "$#{grouped(whole.to_i)}.#{cents}"
    end

    # Token counts reach tens of millions; three significant figures keep the table narrow.
    def compact(number)
      return number.to_s if number < 1000

      value, suffix = number < 999_500 ? [number / 1e3, 'K'] : [number / 1e6, 'M']
      digits = value < 100 ? 1 : 0
      "#{format("%.#{digits}f", value).delete_suffix('.0')}#{suffix}"
    end

    def grouped(number) = number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
  end

  # One row per report label, one column per metric any report measured, and a total.
  # Numbers are rounded for reading; the hidden record copies keep the reported text.
  class UsageRows
    METRICS = [
      ['usd', 'USD'],
      ['credits', 'Codex credits'],
      ['input', 'Input'],
      ['cached_input', 'Cached input'],
      ['output', 'Output'],
      ['reasoning_output', 'Reasoning'],
      ['cache_writes', 'Cache writes']
    ].freeze
    COST = %w[usd credits].freeze
    # A non-breaking hyphen keeps names such as claude-opus-5-5 on one line.
    NO_BREAK_HYPHEN = "\u2011"
    ROUTE = %w[host label provider model routed effort].freeze
    LEGEND = [
      [:unreported?, '— not reported'],
      [:minimum?, '+ some usage not reported, so the amount is a minimum'],
      [:earlier?, 'reports from before this table are listed below and not counted']
    ].freeze
    AMOUNT = /\A(\$)?(\d+(?:\.\d+)?)( \(partial\))?\z/

    # A sum over values some of which went unreported, or an estimate marked partial.
    Amount = Struct.new(:value, :lower_bound)

    # Earlier reports shown below the table are not parsed, so the total is a minimum.
    def initialize(columns, earlier: false)
      @earlier = earlier
      @rows = report_rows(columns)
      @metrics = METRICS.select { |key, _label| @rows.any? { |_label, amounts| amounts[key] } }
      # With earlier reports below, even one row gets a total that shows it is a minimum.
      @rows << ['**Total**', total(columns)] if @rows.size > 1 || @earlier
    end

    def table
      header = ['Report', *@metrics.map(&:last)]
      separator = ['---', *(['---:'] * @metrics.size)]
      body = @rows.map { |label, amounts| [escape(label), *@metrics.map { |key, _| shown(key, amounts[key]) }] }
      [header, separator, *body].map { |row| "| #{row.join(' | ')} |" }.join("\n")
    end

    def summary
      usd = minimum(@rows.last.last['usd'])
      usd && "#{shown('usd', usd)} estimated"
    end

    def glossary = UsageGlossary.for(@metrics)

    def legend
      cells = @rows.flat_map { |_label, amounts| @metrics.map { |key, _| amounts[key] } }
      notes = LEGEND.filter_map { |test, text| text if send(test, cells) }
      "_#{notes.join('; ')}._" unless notes.empty?
    end

    private

    def unreported?(cells) = cells.include?(nil)
    def minimum?(cells) = cells.grep(Amount).any?(&:lower_bound)
    def earlier?(_cells) = @earlier

    # Labels are only unique within one report, so rows also match on the route.
    # A label shared by different routes gains the model and effort that tell them apart.
    def report_rows(columns)
      groups = columns.group_by { |column| column.values_at(*ROUTE) }.values
      shared = groups.map { |group| group.first['label'] }.tally.reject { |_label, count| count == 1 }
      groups.map { |group| [row_label(group, shared), sums(group)] }
    end

    def row_label(group, shared)
      label = group.first['label']
      label = "#{label} (#{route_name(group.first)})" if shared.key?(label)
      group.size > 1 ? "#{label} ×#{group.size}" : label
    end

    def route_name(column)
      model = [column['routed'], column['model']].find { |value| value != 'UNKNOWN' }
      [column['host'], column['provider'], model, column['effort']].reject { |value| value.nil? || value == 'UNKNOWN' }
                                                                   .join(' ')
    end

    # Hosts count input differently (Codex includes cache reads, Claude excludes them), so
    # token columns are not added across rows; only the cost estimates are.
    def total(columns)
      METRICS.to_h do |key, _label|
        [key, COST.include?(key) ? minimum(column_sum(columns, key)) : :blank]
      end
    end

    def minimum(sum) = sum && @earlier ? Amount.new(sum.value, true) : sum

    def sums(group) = METRICS.to_h { |key, _label| [key, column_sum(group, key)] }

    def column_sum(columns, key) = sum(columns.map { |column| amount(column[key]) })

    def sum(amounts)
      known = amounts.compact
      return if known.empty?

      Amount.new(known.sum(&:value), known.size < amounts.size || known.any?(&:lower_bound))
    end

    def amount(text)
      match = AMOUNT.match(text)
      return unless match

      Amount.new(match[2].include?('.') ? match[2].to_f : match[2].to_i, !match[3].nil?)
    end

    def shown(key, amount)
      return '' if amount == :blank
      return '—' unless amount

      text = case key
             when 'usd' then UsageNumbers.usd(amount.value)
             when 'credits' then format('%.2f', amount.value)
             else UsageNumbers.compact(amount.value.to_i)
             end
      amount.lower_bound ? "#{text}+" : text
    end

    def escape(text) = UsagePricing.visible(text.gsub(/[\\|]/) { |character| "\\#{character}" })
  end
end
