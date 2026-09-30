# frozen_string_literal: true

module Shaka
  # Public product stage: early successor to shakacode/agent-workflows.
  # Independent of VERSION and of seam YAML `version: 1`.
  PRODUCT_STAGE = '0.0.x'

  # RubyGems and generated-file identifier. `0.1.0.pre.1` is already published
  # to reserve the name. Stay on `0.1.0.pre.N` so a later `0.0.x` artifact
  # cannot look current while `gem install shaka --pre` still prefers the
  # reservation. Seam-contract version stays independent of this constant.
  VERSION = '0.1.0.pre.1'
end
