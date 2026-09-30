# frozen_string_literal: true

require_relative 'error'

module Shaka
  # The commit and branch a merge run is allowed to land, named before any gate is read.
  #
  # A merge can reach the wrong branch two ways, and neither implies the other. The pull
  # request may never have targeted the branch the change was validated against, because it
  # was retargeted before this run or because a stated base was never applied to a pull
  # request the task adopted. Or its target may move while this run reads gates. Both live
  # here so neither can be dropped without the other being obvious. A head past the size limits
  # also needs a human to confirm it before an agent may land it.
  class MergeTarget
    def self.required!(head, base, limits)
      raise Error, 'Expected a full commit SHA' unless head.is_a?(String) && head.match?(/\A[0-9a-f]{40}\z/)
      return new(head, base, limits) if base.is_a?(String) && !base.strip.empty?

      raise Error, 'Expected the base branch the change was validated against'
    end

    def initialize(head, base, limits)
      @head = head
      @base = base
      @limits = limits
    end

    def validated!(pull)
      unless pull['baseRefName'] == @base
        raise Error, "PR targets #{pull['baseRefName'].inspect}, not the validated base #{@base.inspect}"
      end

      @limits.verify!(pull, @head)
    end

    # The size is rechecked so the counts that gate submission come from the last snapshot read.
    def unchanged!(initial, current)
      unless current['baseRefName'] == initial['baseRefName']
        raise Error, 'PR base changed; refresh verification and walkthrough'
      end

      @limits.verify!(current, @head)
    end
  end
end
