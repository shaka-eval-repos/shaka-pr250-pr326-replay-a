# frozen_string_literal: true

module Shaka
  # Identifies paths owned by the candidate checkout.
  module LocalReviewExecutable
    def self.candidate_owned?(target, root) = target == root || target.start_with?("#{root}/")
  end
end
