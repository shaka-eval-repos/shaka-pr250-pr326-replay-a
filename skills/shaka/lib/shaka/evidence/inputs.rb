# frozen_string_literal: true

require_relative '../configuration'
require_relative '../configuration/fingerprint'
require_relative '../doctor/installation_identity'

module Shaka
  module Evidence
    # Resolve the same private or trusted configuration used by an operation.
    class Inputs
      def self.capture(root:, ref:, repository:, task_overrides: {})
        config, selected, kind = resolve_source(root, ref)
        fingerprint = Configuration::Fingerprint.build(
          root:, effective_settings: config.to_h.merge('task_overrides' => task_overrides), repository:,
          installation: Doctor::InstallationIdentity.read, **selected
        )
        [config, fingerprint.to_h, kind]
      end

      def self.resolve_source(root, ref)
        source = Configuration.private_source(root:, ref:)
        if source.status == 'complete'
          [source.candidate_config, { private_source: source }, 'private/local']
        else
          [Configuration.trusted(root:, ref:), { trusted_ref: ref }, 'trusted/team']
        end
      end
    end
  end
end
