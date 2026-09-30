# frozen_string_literal: true

module Shaka
  module Install
    # Serializes complete link switches for one host skills directory.
    module LinkLock
      private

      def with_lock(skills_dir)
        path = File.join(skills_dir, '.shaka-install.lock')
        raise ArgumentError, "Refusing symlinked install lock: #{path}" if File.symlink?(path)

        flags = File::RDWR | File::CREAT
        flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
        File.open(path, flags, 0o600) do |file|
          raise IOError, 'Could not lock skills directory' unless file.flock(File::LOCK_EX)

          yield
        end
      end
    end
  end
end
