# frozen_string_literal: true

require_relative 'initializer'
require_relative 'private_recovery'

module Shaka
  class Seam
    # Prepares local recovery and exclusion before placing generated private files.
    class PrivateSetup < Initializer
      def initialize(root:, ref:, options:)
        super(root:, options:)
        @root = File.realpath(root)
        @ref = ref
      end

      def setup
        files = generated_files
        refuse_trusted_or_adopted!
        recovery = PrivateRecovery.new(root: @root)
        resumable = preflight(recovery, files)
        activate(recovery, files, resumable)
        verify_complete!(recovery)
        recovery.mark_activated!
        recovery.inspect_checkout.merge('status' => 'complete')
      rescue SystemCallError => e
        raise interrupted_error(e, recovery)
      end

      private

      def interrupted_error(error, recovery)
        guidance = recovery ? "; inspect #{recovery.storage} before retrying" : ''
        Error.new("Private setup interrupted at #{error.message}#{guidance}")
      end

      def merge_policy = { 'preference' => 'ask' }

      def validate_policies
        RepositoryConfig::ReviewSchema.new(review_policy).validate
        RepositoryConfig::MergeSchema.new(merge_policy).validate
      end

      def refuse_trusted_or_adopted!
        validate_policies
        refuse_legacy_configuration!
        source = Configuration.private_source(root: @root, ref: @ref)
        raise Error, 'Trusted Shaka configuration already exists; private setup is unavailable' if
          source.trusted_source == 'present'

        refuse_adoption!(PrivateRecovery.new(root: @root, assign_identity: false))
      end

      def preflight(recovery, files)
        resumable = source_available?(recovery, files)
        refuse_adoption!(recovery)
        preflight_destinations(files)
        resumable
      end

      def source_available?(recovery, files)
        source = Configuration.private_source(root: @root, ref: @ref)
        resumable = recovery.prepared_matches?(files)
        refuse_copy_replacement!(source, recovery, resumable)
        raise Error, "Private setup blocked (#{source.status}): #{source.blockers.join('; ')}" unless
          source.status == 'absent' || resumable

        resumable
      end

      def refuse_copy_replacement!(source, recovery, resumable)
        return unless source.status == 'absent' && recovery.recovery_copy? && !resumable

        raise Error, "Existing recovery copy differs from proposed setup: #{recovery.storage}; compare before retrying"
      end

      def refuse_adoption!(recovery)
        adopted = recovery.adoption_paths
        raise Error, "Tracked Shaka configuration: #{adopted.join(', ')}" if adopted.any?
      end

      def preflight_destinations(files)
        preflight_directories
        preflight_files(files)
        preflight_permissions(files)
      end

      def activate(recovery, files, resumable)
        recovery.prepare(files) unless resumable
        recovery.exclude!
        recovery.mark_incomplete!
        write_files(files)
      end

      def verify_complete!(recovery)
        result = Configuration.private_source(root: @root, ref: @ref)
        raise Error, "Private setup incomplete; recover from #{recovery.storage}: #{result.blockers.join('; ')}" unless
          result.status == 'complete'
      end

      def generated_files
        files = super.reject { |path, _| path == Configuration.path(@root, :POINTER) }
        files.merge(optional_files)
      end

      def optional_files
        optional = %i[validate_local trigger_hosted_ci]
        present = optional.select { |name| @options.key?(:"#{name}_command") }
        raise Error, 'validate-local and trigger-hosted-ci commands must be supplied together' if present.length == 1

        present.to_h do |name|
          path = Configuration::Paths.at(@root, Initializer::LAYOUT.optional.fetch(name.to_s))
          [path, wrapper(command_arguments(@options.fetch(:"#{name}_command"), name))]
        end
      end
    end
  end
end
