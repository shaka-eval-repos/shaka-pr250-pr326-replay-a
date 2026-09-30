# frozen_string_literal: true

require_relative '../error'
require_relative '../repository_config/review_schema'

module Shaka
  class Seam
    # CLI review/merge flags fill missing policy and refuse to override from-ref values.
    module MigrationPolicy
      private

      def overlay_explicit_policy(classified)
        overlay_review(classified) if @options[:review_policy]
        overlay_merge(classified) if @options[:merge_preference]
        classified.blocking.delete('review.required') if classified.established.dig('review', 'required')
        check = RepositoryConfig::ReviewSchema::CI_REVIEW_JOBS
        classified.blocking.delete("review.#{check}") if ci_review_jobs_resolved?(classified)
        classified.blocking.delete('merge.preference') if classified.established.dig('merge', 'preference')
      end

      def ci_review_jobs_resolved?(classified)
        review = classified.established['review'] || {}
        review['required'] == 'none' || review[RepositoryConfig::ReviewSchema::CI_REVIEW_JOBS]
      end

      def overlay_review(classified)
        require_review_flags!
        existing = classified.established['review'] || {}
        check = RepositoryConfig::ReviewSchema::CI_REVIEW_JOBS
        refuse_policy_override('--review-policy', 'review.required', existing['required'], @options[:review_policy])
        refuse_policy_override('--ci-review-job', "review.#{check}", existing[check], @options[:ci_review_jobs])
        classified.established['review'] = existing.merge(review_overlay)
      end

      def require_review_flags!
        none = @options[:review_policy] == 'none'
        names = @options[:ci_review_jobs]
        raise Error, '--ci-review-job must be omitted when review policy is none' if none && names
        raise Error, '--ci-review-job is required' if !none && (names.nil? || names.empty?)
      end

      def review_overlay
        overlay = { 'required' => @options[:review_policy] }
        names = @options[:ci_review_jobs]
        overlay[RepositoryConfig::ReviewSchema::CI_REVIEW_JOBS] = names if names
        overlay
      end

      def overlay_merge(classified)
        existing = classified.established['merge'] || {}
        refuse_policy_override('--merge-preference', 'merge.preference', existing['preference'],
                               @options[:merge_preference])
        classified.established['merge'] = existing.merge('preference' => @options[:merge_preference])
      end

      def refuse_policy_override(flag, field, established, requested)
        return if established.nil? || requested.nil? || established == requested

        raise Error, "#{flag} contradicts #{field} established at from-ref"
      end
    end
  end
end
