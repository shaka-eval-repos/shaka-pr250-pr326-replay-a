# frozen_string_literal: true

module Shaka
  module Configuration
    # Git root lookup shared by seam init wrappers and layout upgrade repairs.
    module WrapperTemplate
      SHELL_ROOT = 'root=$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX ' \
                   '-u GIT_CEILING_DIRECTORIES ' \
                   'git -C "$(dirname -- "$0")" rev-parse --show-toplevel) || exit $?'
    end
  end
end
