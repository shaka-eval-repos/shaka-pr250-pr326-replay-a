# frozen_string_literal: true

module Shaka
  class PrWatch
    # Applies the trusted none/one/all review wait to configured CI job runs.
    module ReviewGate
      private

      def review_jobs_terminal?(checks)
        return true if @ci_jobs.empty? || @ci_wait == 'none'

        results = @ci_jobs.map do |name|
          rows = checks.select { |row| row['name'] == name }
          !rows.empty? && terminal?(rows)
        end
        @ci_wait == 'all' ? results.all? : results.any?
      end
    end
  end
end
