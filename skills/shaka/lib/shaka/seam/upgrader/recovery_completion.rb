# frozen_string_literal: true

module Shaka
  class Seam
    class Upgrader
      # Finishes a validated migration when only journal cleanup was interrupted.
      module RecoveryCompletion
        private

        def completed_upgrade?(journal)
          journal.fetch('desired').all? do |path, state|
            UpgradePlan.new(@root).snapshot(path) == state
          end
        end

        def finish_completed_upgrade(journal)
          verify_temporary_states!(journal)
          journal.fetch('temporary').each { |relative| remove_state(File.join(@root, relative)) }
          cleanup_owned_journal_temp
          File.delete(journal_path)
          puts JSON.generate('mode' => 'recover', 'status' => 'completed',
                             'paths' => journal.fetch('desired').keys.sort)
          0
        end
      end
    end
  end
end
